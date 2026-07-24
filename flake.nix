{
  description = "Self-maintained Nix packages for Bisq 1 (bisq-desktop) and Bisq 2 (bisq2), built from Bisq's official prebuilt, GPG-signed .deb releases.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems f;
      pkgsFor = system: import nixpkgs {
        inherit system;
        config.allowUnfree = true; # Azul Zulu JDK (used by bisq2) is unfree
      };
    in
    {
      packages = forAllSystems (system:
        let pkgs = pkgsFor system; in
        {
          bisq-desktop = pkgs.callPackage ./pkgs/bisq-desktop { };
          bisq2 = pkgs.callPackage ./pkgs/bisq2 { };
          default = self.packages.${system}.bisq-desktop;
        });

      # Consumers can either use the packages output above, or add this overlay
      # to their own nixpkgs so `pkgs.bisq-desktop` / `pkgs.bisq2` resolve.
      overlays.default = final: _prev: {
        bisq-desktop = final.callPackage ./pkgs/bisq-desktop { };
        bisq2 = final.callPackage ./pkgs/bisq2 { };
      };
    };
}
