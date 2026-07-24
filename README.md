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

The volatile fields (`version` + the two `.deb`/signature hashes) live in
`pkgs/<pkg>/source.json`; each derivation reads them via `lib.importJSON`. You
never hand-edit hashes inside the `.nix` files.

**Automatic (recommended).** The [`update-bisq`](.github/workflows/update-bisq.yml)
GitHub Action runs weekly (and on manual dispatch). For any package with a newer
upstream release it rewrites `source.json`, builds + GPG-verifies the package in
CI, and opens a PR. You just review the `source.json` diff and merge.

**Manual.** Run the same updater locally:

```bash
./update.sh              # check/update both packages
./update.sh bisq2        # just one
nix build .#bisq-desktop .#bisq2   # verify (build fails if GPG verification fails)
```

Or edit `source.json` by hand and `nix build`. The signing-key `.asc` hashes are
still pinned inline in the `.nix` files and only change if Bisq rotates keys.

## Build / verify

```bash
nix build .#bisq-desktop .#bisq2
```

## Provenance

- `bisq-desktop` adapted from [`emmanuelrosa/btc-clients-nix`](https://github.com/emmanuelrosa/btc-clients-nix).
- `bisq2` adapted from [`nixpkgs`](https://github.com/NixOS/nixpkgs) `pkgs/by-name/bi/bisq2`.

Not affiliated with or endorsed by the Bisq project. Bisq is MIT-licensed.
