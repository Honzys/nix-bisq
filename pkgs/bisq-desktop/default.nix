# Bisq 1 (bisq-desktop) — packaged here so we own the version bumps and
# never wait on an external Nix maintainer. See the repo README.
#
# Provenance: adapted from emmanuelrosa/btc-clients-nix (pkgs/bisq/default.nix).
# It does NOT build from source — it downloads Bisq's official prebuilt .deb from
# GitHub Releases, GPG-verifies it against Bisq's signing keys, and repackages it
# for Nix. That makes a version bump a 3-field change.
#
#   version + the deb/signature hashes live in ./source.json. To bump: run
#   `./update.sh` from the repo root (or let the weekly GitHub Action do it), or
#   edit source.json by hand. The two publicKey hashes below only change if Bisq
#   rotates signing keys (rare).
{ stdenv
, lib
, makeWrapper
, fetchurl
, makeDesktopItem
, copyDesktopItems
, imagemagick
, openjdk21
, dpkg
, writeScript
, bash
, stripJavaArchivesHook
, pkgsStatic
, torsocks
, zip
, unzip
, findutils
, procps
, coreutils
}:

let
  source = lib.importJSON ./source.json;
  version = source.version;
  archiveName = "Bisq-64bit-${version}.deb";
  jdk = openjdk21.override { enableJavaFX = true; };

  bisq-launcher = args: writeScript "bisq-launcher" ''
    #! ${bash}/bin/bash
    PATH="${lib.makeBinPath [ coreutils procps ]}:$PATH"

    # Bisq only re-extracts its bundled Tor when this version file mismatches;
    # drop it so a rebuilt Nix Tor is picked up. Don't wipe the dir like Bisq 2
    # does: it holds the onion service keys (hiddenservice/).
    rm -f "$HOME/.local/share/Bisq/btc_mainnet/tor/bin/version"

    classpath=@out@/lib/desktop.jar:@out@/lib/*

    exec "${jdk}/bin/java" -Djpackage.app-version=@version@ -XX:MaxRAM=8g -Xss1280k -XX:+UseG1GC -XX:MaxHeapFreeRatio=10 -XX:MinHeapFreeRatio=5 -XX:+UseStringDeduplication -Djava.net.preferIPv4Stack=true --add-exports=javafx.graphics/com.sun.javafx.scene=ALL-UNNAMED --add-exports=javafx.controls/com.sun.javafx.scene.control=ALL-UNNAMED --add-exports=javafx.controls/com.sun.javafx.scene.control.behavior=ALL-UNNAMED --add-opens=javafx.controls/javafx.scene.control.skin=ALL-UNNAMED -classpath $classpath ${args} bisq.desktop.app.BisqAppMain "$@"
  '';

  # Since 1.10.11 Bisq runs Tor in a sandbox (sandy) that only lets it exec
  # files in its own bin dir — no /nix/store interpreter or libraries. A static
  # Tor needs neither. For musl-static: systemd isn't available, torsocks (only
  # used by the torify script) fails to link, -lgcc_s has no static lib, and
  # test-memwipe segfaults by design (reads freed memory) under musl malloc.
  tor = (pkgsStatic.tor.override { systemd = null; inherit torsocks; }).overrideAttrs {
    env = { };
    doCheck = false;
  };
in
stdenv.mkDerivation (finalAttrs: {
  inherit version;
  pname = "bisq-desktop";

  src = fetchurl {
    url = "https://github.com/bisq-network/bisq/releases/download/v${finalAttrs.version}/${archiveName}";
    hash = source.debHash;
  };

  nativeBuildInputs = [
    copyDesktopItems
    dpkg
    imagemagick
    makeWrapper
    stripJavaArchivesHook
    zip
    unzip
    findutils
  ];

  desktopItems = [
    (makeDesktopItem {
      name = "Bisq";
      exec = "bisq-desktop";
      icon = "bisq";
      desktopName = "Bisq ${finalAttrs.version}";
      genericName = "Decentralized bitcoin exchange";
      categories = [ "Network" "P2P" ];
    })

    (makeDesktopItem {
      name = "Bisq-hidpi";
      exec = "bisq-desktop-hidpi";
      icon = "bisq";
      desktopName = "Bisq ${finalAttrs.version} (HiDPI)";
      genericName = "Decentralized bitcoin exchange";
      categories = [ "Network" "P2P" ];
    })
  ];

  unpackPhase = ''
    dpkg -x $src .
  '';

  preUnpack = let
    signature = fetchurl {
      url = "https://github.com/bisq-network/bisq/releases/download/v${finalAttrs.version}/${archiveName}.asc";
      hash = source.sigHash;
    };

    publicKey = {
      "E222AA02" = fetchurl {
        url = "https://github.com/bisq-network/bisq/releases/download/v${finalAttrs.version}/E222AA02.asc";
        hash = "sha256-Ue/UmS6F440/ybEEIAR+pdPEIksAt6QSMN6G5TZVWzc=";
      };

      "4A133008" = fetchurl {
        url = "https://github.com/bisq-network/bisq/releases/download/v${finalAttrs.version}/4A133008.asc";
        hash = "sha256-UijG3DkJNNTakVJd2wl30mDepa27n6R/Xxfl4sjt0sk=";
      };
    };
  in ''
    pushd $(mktemp -d)
    export GNUPGHOME=./gnupg
    mkdir -m 700 -p $GNUPGHOME
    ln -s $src ./${archiveName}
    ln -s ${signature} ./signature.asc
    gpg --import ${publicKey."E222AA02"}
    gpg --import ${publicKey."4A133008"}
    gpg --batch --verify signature.asc ${archiveName}
    popd
  '';

  buildPhase = ''
    # Replace the Tor binary in tor.zip (inside tor-*.jar) with the one from
    # Nixpkgs, keeping the rest of the bundle (geoip, torrc-defaults, ...).

    tor_jar_file=$(find ./opt/bisq/lib/app -name "tor-[0-9]*.jar")
    test -n "$tor_jar_file"
    unzip -p $tor_jar_file tor.zip > tor.zip
    install -m 755 ${tor}/bin/tor ./tor
    zip tor.zip ./tor
    zip $tor_jar_file tor.zip
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out $out/bin
    cp -r opt/bisq/lib/app $out/lib

    install -D -m 777 ${bisq-launcher ""} $out/bin/bisq-desktop
    substituteAllInPlace $out/bin/bisq-desktop

    install -D -m 777 ${bisq-launcher "-Dglass.gtk.uiScale=2.0"} $out/bin/bisq-desktop-hidpi
    substituteAllInPlace $out/bin/bisq-desktop-hidpi

    for n in 16 24 32 48 64 96 128 256; do
      size=$n"x"$n
      convert opt/bisq/lib/Bisq.png -resize $size bisq.png
      install -Dm644 -t $out/share/icons/hicolor/$size/apps bisq.png
    done;

    runHook postInstall
  '';

  meta = with lib; {
    description = "Decentralized bitcoin exchange network";
    homepage = "https://bisq.network";
    sourceProvenance = with sourceTypes; [ binaryBytecode ];
    license = licenses.mit;
    maintainers = with maintainers; [ emmanuelrosa ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "bisq-desktop";
  };
})
