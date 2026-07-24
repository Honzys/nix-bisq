#!/usr/bin/env bash
# Bump a Bisq package's source.json to the latest upstream GitHub release.
# Looks up the latest release tag first and only downloads the (large) .deb +
# detached signature when a newer version exists, recording their SRI hashes.
#
# Usage:
#   ./update.sh                # check/update every package
#   ./update.sh bisq-desktop   # check/update a single package
#
# Requires: nix, jq, and gh (uses GITHUB_TOKEN in CI) or curl for the lookup.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# name           upstream-repo       deb-filename-template (@V@ = version)
packages=(
  "bisq-desktop  bisq-network/bisq   Bisq-64bit-@V@.deb"
  "bisq2         bisq-network/bisq2  Bisq-@V@.deb"
)

latest_release() {
  # Prefer gh (authenticated in CI); fall back to the public REST API via curl.
  local repo="$1"
  if command -v gh >/dev/null 2>&1; then
    gh api "repos/$repo/releases/latest" --jq '.tag_name'
  else
    curl -fsSL "https://api.github.com/repos/$repo/releases/latest" | jq -r '.tag_name'
  fi
}

sri_hash() {
  nix store prefetch-file --json "$1" | jq -r '.hash'
}

for entry in "${packages[@]}"; do
  read -r name repo tmpl <<<"$entry"
  # Optional single-package filter.
  if [[ $# -gt 0 && "$1" != "$name" ]]; then continue; fi

  json="$here/pkgs/$name/source.json"
  current="$(jq -r '.version' "$json")"
  tag="$(latest_release "$repo")"
  latest="${tag#v}"

  if [[ "$latest" == "$current" ]]; then
    echo "$name: up to date ($current)"
    continue
  fi

  echo "$name: $current -> $latest (fetching release assets to hash them…)"
  deb="${tmpl//@V@/$latest}"
  base="https://github.com/$repo/releases/download/v$latest"
  debHash="$(sri_hash "$base/$deb")"
  sigHash="$(sri_hash "$base/$deb.asc")"

  jq --arg v "$latest" --arg d "$debHash" --arg s "$sigHash" \
    '.version = $v | .debHash = $d | .sigHash = $s' "$json" >"$json.tmp"
  mv "$json.tmp" "$json"
  echo "$name: wrote $json (build to verify: nix build .#$name)"
done
