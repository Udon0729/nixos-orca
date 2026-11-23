#!/usr/bin/env bash
# Points sources.json at a stablyai/orca release: the latest one, or the tag given as $1.
# Needs gh, jq and python3. Writes changed/old/new to $GITHUB_OUTPUT when it is set.
set -euo pipefail
cd "$(dirname "$0")/.."

repo="stablyai/orca"
asset="orca-linux.AppImage"

if [ -n "${1:-}" ]; then
  release="$(gh api "repos/$repo/releases/tags/$1")"
else
  release="$(gh api "repos/$repo/releases/latest")"
fi

tag="$(jq -r .tag_name <<<"$release")"
[[ $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "unexpected release tag: $tag" >&2; exit 1; }

digest="$(jq -r --arg a "$asset" '.assets[] | select(.name == $a) | .digest' <<<"$release")"
[[ $digest =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "$tag has no sha256 digest for $asset" >&2; exit 1; }

old="$(jq -r .version sources.json)"
new="${tag#v}"
hash="$(python3 -c 'import base64, sys; print("sha256-" + base64.b64encode(bytes.fromhex(sys.argv[1])).decode())' "${digest#sha256:}")"

jq -n --arg v "$new" --arg u "https://github.com/$repo/releases/download/$tag/$asset" --arg h "$hash" \
  '{version: $v, url: $u, hash: $h}' >sources.json.tmp
mv sources.json.tmp sources.json

if git diff --quiet -- sources.json; then changed=false; else changed=true; fi
echo "pin: $old -> $new (changed=$changed)"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  printf 'changed=%s\nold=%s\nnew=%s\n' "$changed" "$old" "$new" >>"$GITHUB_OUTPUT"
fi
