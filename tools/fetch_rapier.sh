#!/usr/bin/env bash
# Downloads the pinned Rapier2D build used by the demo and tests.
set -euo pipefail

VERSION="0.36.0"
FLAVOR="godot-rapier-2d-single"
SHA256="6c2c8ea8ac036ad9698ca511ab0117c873524d08d9f34e25c1873b71accf542a"
URL="https://github.com/appsinacup/godot-rapier-physics/releases/download/v${VERSION}/${FLAVOR}.zip"

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
target="$repo_root/addons/godot-rapier2d"

if grep -q "^version=\"$VERSION\"" "$target/plugin.info.cfg" 2>/dev/null; then
    echo "Rapier2D $VERSION is already installed at $target."
    exit 0
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

echo "Downloading Rapier2D $VERSION..."
curl -fsSL --retry 3 --retry-delay 2 -o "$tmp_dir/rapier.zip" "$URL"
echo "$SHA256  $tmp_dir/rapier.zip" | sha256sum -c -

unzip -q "$tmp_dir/rapier.zip" -d "$tmp_dir"
rm -rf "$target"
mv "$tmp_dir/$FLAVOR/addons/godot-rapier2d" "$repo_root/addons/"

echo "Installed Rapier2D $VERSION at $target."
