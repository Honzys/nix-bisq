# nix-bisq

Self-maintained Nix packages for **Bisq 1** (`bisq-desktop`) and **Bisq 2**
(`bisq2`), so updates never wait on an upstream Nix maintainer.

Neither package builds from source. Each downloads Bisq's **official prebuilt,
GPG-signed `.deb`** from GitHub Releases, verifies the signature against Bisq's
signing keys, swaps the embedded Tor binary for the Nixpkgs one, and repackages
it. A version bump is therefore a 3-field change (`version` + two `sha256`
hashes) — see the header comment in each `pkgs/*/default.nix`.

## Packages

| Attr | App | Version |
|------|-----|---------|
| `bisq-desktop` | Bisq 1 | 1.10.4 |
| `bisq2` | Bisq 2 | 2.1.11 |

## Use

```nix
# flake.nix
inputs.nix-bisq.url = "github:OWNER/nix-bisq";
# recommended: reuse your existing unstable nixpkgs to avoid a duplicate eval
inputs.nix-bisq.inputs.nixpkgs.follows = "nixpkgs-unstable";
```

Then either consume the package outputs:

```nix
environment.systemPackages = [ inputs.nix-bisq.packages.${system}.bisq2 ];
```

or add the overlay so `pkgs.bisq-desktop` / `pkgs.bisq2` resolve:

```nix
nixpkgs.overlays = [ inputs.nix-bisq.overlays.default ];
```

## Updating to a new Bisq release

```bash
# Bisq 1 (bisq-desktop), e.g. 1.10.5
nix store prefetch-file "https://github.com/bisq-network/bisq/releases/download/v1.10.5/Bisq-64bit-1.10.5.deb"
nix store prefetch-file "https://github.com/bisq-network/bisq/releases/download/v1.10.5/Bisq-64bit-1.10.5.deb.asc"

# Bisq 2 (bisq2), e.g. 2.1.12
nix store prefetch-file "https://github.com/bisq-network/bisq2/releases/download/v2.1.12/Bisq-2.1.12.deb"
nix store prefetch-file "https://github.com/bisq-network/bisq2/releases/download/v2.1.12/Bisq-2.1.12.deb.asc"
```

Paste the printed `sha256-…` values into `version` + `src.hash` + `signature.hash`
in the matching `pkgs/<pkg>/default.nix`, then `nix build .#<pkg>` to verify (the
build fails if GPG verification fails). The signing-key `.asc` hashes only change
if Bisq rotates keys.

## Build / verify

```bash
nix build .#bisq-desktop .#bisq2
```

## Provenance

- `bisq-desktop` adapted from [`emmanuelrosa/btc-clients-nix`](https://github.com/emmanuelrosa/btc-clients-nix).
- `bisq2` adapted from [`nixpkgs`](https://github.com/NixOS/nixpkgs) `pkgs/by-name/bi/bisq2`.

Not affiliated with or endorsed by the Bisq project. Bisq is MIT-licensed.
