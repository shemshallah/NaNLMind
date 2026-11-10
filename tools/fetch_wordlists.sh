#!/usr/bin/env bash
set -euo pipefail

repo="${NANROUTER_REPO:-shemshallah/NaNROUTER}"
tag="${WORDLIST_RELEASE_TAG:-wordlists-latest}"
bundle="${1:-/storage/emulated/0/Download/NaNROUTER-wordlists}"
dest="${2:-../NaNROUTER/corpora/wordlists}"

mkdir -p "$bundle" "$dest"
dest="$(cd "$dest" && pwd)"
gh release download "$tag" -R "$repo" --dir "$bundle" \
  --pattern 'NaNROUTER-wordlists.tar.zst.part-*' \
  --pattern 'SHA256SUMS.parts' --clobber

(
  cd "$bundle"
  sed 's#  \.\./#  #' SHA256SUMS.parts | sha256sum -c -
  cat NaNROUTER-wordlists.tar.zst.part-* | tar --zstd -xf - -C "$dest"
)

echo "WORDLIST_BUNDLE_READY dest=$dest bytes=$(du -sh "$dest" | cut -f1)"
