#!/usr/bin/env bash
# Verifies that addons/ragdoll2d works without the demo project.
#
# Copies only the addon, the pinned Rapier2D build and the smoke test into a
# temporary minimal project, imports it and runs the smoke test there. This
# catches accidental dependencies on demo files or project settings.
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# Override with GODOT=/path/to/godot when the binary is not on PATH.
godot="${GODOT:-godot}"
rapier="$repo_root/addons/godot-rapier2d"

if [[ ! -d "$rapier" ]]; then
    echo "Rapier2D is missing at $rapier. Run tools/fetch_rapier.sh first." >&2
    exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/addons" "$tmp_dir/tests"
cp -R "$repo_root/addons/ragdoll2d" "$tmp_dir/addons/ragdoll2d"
cp -R "$rapier" "$tmp_dir/addons/godot-rapier2d"
cp "$repo_root/tests/smoke_test.gd" "$repo_root/tests/smoke_test.tscn" "$tmp_dir/tests/"

cat > "$tmp_dir/project.godot" <<'EOF'
; Minimal project used by tools/test_addon_isolated.sh.
config_version=5

[application]

config/name="Ragdoll 2D addon isolation test"
config/features=PackedStringArray("4.7")

[physics]

common/physics_ticks_per_second=120
2d/physics_engine="Rapier2D"
EOF

echo "Importing isolated project at $tmp_dir"
"$godot" --headless --path "$tmp_dir" --import --quit-after 60

echo "Running smoke test in isolated project"
"$godot" --headless --path "$tmp_dir" res://tests/smoke_test.tscn
