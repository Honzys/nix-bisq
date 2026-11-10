# Since Bisq 1.10.11 / 2.1.15, both apps run Tor in a sandbox (sandy) that only
# lets it exec files in its own bin dir — no /nix/store interpreter, libraries
# or wrapper scripts. A loader-free static Tor needs none of them.
# For musl-static: systemdLibs isn't available, torsocks (only used by the
# torify script) fails to link, -lgcc_s has no static lib (so the package's
# env is replaced), and test-memwipe segfaults by design under musl malloc.
# pkgsStatic links a PIE with a /nix/store musl loader by default; -static
# forces a loader-free binary.
{ pkgsStatic, torsocks }:

(pkgsStatic.tor.override { systemdLibs = null; inherit torsocks; }).overrideAttrs {
  env.NIX_CFLAGS_LINK = "-static";
  doCheck = false;
  postFixup = ''
    $READELF -l $out/bin/tor > tor.phdr
    if grep -q INTERP tor.phdr; then
      echo "tor has an ELF interpreter; sandy can't exec it" >&2
      exit 1
    fi
  '';
}
