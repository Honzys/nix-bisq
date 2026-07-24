# Bisq 2 (bisq2) — adapted from nixpkgs (pkgs/by-name/bi/bisq2/package.nix).
#
# Like bisq-desktop, this does NOT build from source: it downloads Bisq's official
# prebuilt .deb from GitHub Releases, GPG-verifies it against Bisq's signing keys,
# swaps the embedded Tor binary for the Nixpkgs one, and repackages it.
#
#   To update to a new Bisq 2 release vX.Y.Z:
#     1. version        = "X.Y.Z";
#     2. src.hash            -> nix store prefetch-file \
#          "https://github.com/bisq-network/bisq2/releases/download/vX.Y.Z/Bisq-X.Y.Z.deb"
#     3. signature.hash      -> nix store prefetch-file \
#          "https://github.com/bisq-network/bisq2/releases/download/vX.Y.Z/Bisq-X.Y.Z.deb.asc"
#   A release is signed by ONE of the two keys below (see signingkey.asc in the
#   release); both are imported so either signature verifies. Update a publicKey
#   hash only if Bisq rotates that key.
#
# The nixpkgs `passthru.webcam-app` (a maintainer QR-scan test package) is dropped
# here, along with its callPackage/socat/unzip inputs — we don't need it.
{
  stdenv,
  lib,
  makeBinaryWrapper,
  fetchurl,
  makeDesktopItem,
  copyDesktopItems,
  imagemagick,
  zulu25,
  dpkg,
  writeShellScript,
  tor,
  zip,
  gnupg,
  coreutils,

  # Bundled webcam-app runtime library
  libv4l,
}:

let
  version = "2.1.11";

  jdk = zulu25.override { enableJavaFX = true; };

  bisq-launcher =
    args:
    writeShellScript "bisq-launcher" ''
      rm -fR $HOME/.local/share/Bisq2/tor

      exec "${lib.getExe jdk}" -Djpackage.app-version=@version@ -classpath @out@/lib/app/desktop-app-launcher.jar:@out@/lib/app/* ${args} bisq.desktop_app_launcher.DesktopAppLauncher "$@"
    '';

  # A given release will be signed by either Alejandro Garcia or Henrik Jannsen
  # as indicated in the file
  # https://github.com/bisq-network/bisq2/releases/download/v${version}/signingkey.asc
  publicKey = {
    "E222AA02" = fetchurl {
      url = "https://github.com/bisq-network/bisq2/releases/download/v${version}/E222AA02.asc";
      hash = "sha256-31uBpe/+0QQwFyAsoCt1TUWRm0PHfCFOGOx1M16efoE=";
    };

    "387C8307" = fetchurl {
      url = "https://github.com/bisq-network/bisq2/releases/download/v${version}/387C8307.asc";
      hash = "sha256-PrRYZLT0xv82dUscOBgQGKNf6zwzWUDhriAffZbNpmI=";
    };
  };

  binPath = lib.makeBinPath [
    coreutils
    tor
  ];

  libraryPath = lib.makeLibraryPath [
    stdenv.cc.cc
    libv4l
  ];
in
stdenv.mkDerivation (finalAttrs: {
  inherit version;

  pname = "bisq2";

  src = fetchurl {
    url = "https://github.com/bisq-network/bisq2/releases/download/v${version}/Bisq-${version}.deb";
    hash = "sha256-Ts0u1Rapgfz/z17U3VSN17/rdACr/KOGmiZjWnGJmcw=";

    # Verify the upstream Debian package prior to extraction, so a successful
    # build requires the .deb to pass GPG verification.
    nativeBuildInputs = [ gnupg ];
    downloadToTemp = true;

    postFetch = ''
      pushd $(mktemp -d)
      export GNUPGHOME=./gnupg
      mkdir -m 700 -p $GNUPGHOME
      ln -s $downloadedFile ./Bisq-${version}.deb
      ln -s ${finalAttrs.signature} ./signature.asc
      gpg --import ${publicKey."E222AA02"}
      gpg --import ${publicKey."387C8307"}
      gpg --batch --verify signature.asc Bisq-${version}.deb
      popd
      mv $downloadedFile $out
    '';
  };

  signature = fetchurl {
    url = "https://github.com/bisq-network/bisq2/releases/download/v${version}/Bisq-${version}.deb.asc";
    hash = "sha256-/+HDj28uOFQwkrrzKfcQW0T5/qTIeB30Zd10EjeGhlU=";
  };

  nativeBuildInputs = [
    copyDesktopItems
    dpkg
    imagemagick
    makeBinaryWrapper
    zip
    gnupg
  ];

  desktopItems = [
    (makeDesktopItem {
      name = "bisq2";
      exec = "bisq2";
      icon = "bisq2";
      desktopName = "Bisq 2";
      genericName = "Decentralized bitcoin exchange";
      categories = [
        "Network"
        "P2P"
      ];
    })

    (makeDesktopItem {
      name = "bisq2-hidpi";
      exec = "bisq2-hidpi";
      icon = "bisq2";
      desktopName = "Bisq 2 (HiDPI)";
      genericName = "Decentralized bitcoin exchange";
      categories = [
        "Network"
        "P2P"
      ];
    })
  ];

  unpackPhase = ''
    dpkg -x $src .
  '';

  buildPhase = ''
    # Replace the Tor binary embedded in tor.jar (which is in the zip archive tor.zip)
    # with the Tor binary from Nixpkgs.

    makeWrapper ${lib.getExe' tor "tor"} ./tor
    zip tor.zip ./tor
    zip opt/bisq2/lib/app/tor.jar tor.zip
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib $out/bin
    cp -r opt/bisq2/lib/app $out/lib

    install -D -m 777 ${bisq-launcher ""} $out/bin/bisq2
    substituteAllInPlace $out/bin/bisq2
    wrapProgram $out/bin/bisq2 --prefix PATH : ${binPath} --prefix LD_LIBRARY_PATH : ${libraryPath}

    install -D -m 777 ${bisq-launcher "-Dglass.gtk.uiScale=2.0"} $out/bin/bisq2-hidpi
    substituteAllInPlace $out/bin/bisq2-hidpi
    wrapProgram $out/bin/bisq2-hidpi --prefix PATH : ${binPath} --prefix LD_LIBRARY_PATH : ${libraryPath}

    for n in 16 24 32 48 64 96 128 256; do
      size=$n"x"$n
      magick convert opt/bisq2/lib/Bisq2.png -resize $size bisq2.png
      install -Dm644 -t $out/share/icons/hicolor/$size/apps bisq2.png
    done;

    runHook postInstall
  '';

  meta = {
    description = "Decentralized bitcoin exchange network";
    homepage = "https://bisq.network";
    mainProgram = "bisq2";
    sourceProvenance = with lib.sourceTypes; [
      binaryBytecode
    ];
    license = lib.licenses.mit;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
})
