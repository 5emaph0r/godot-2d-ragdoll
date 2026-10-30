# Changelog

All notable changes to Ragdoll 2D are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-10-30

### Added

- Initial public release of the addon.
- Ten-body procedural 2D humanoid ragdoll with standing, walking, jumping,
  crawling, stand-up search and ragdoll mode.
- `Ragdoll2DFigureType` and `Ragdoll2DLimbSpec` resources for body layout and
  tuning.
- `Ragdoll2DImpactFx` with impact and hurt sounds plus blood particles.
- World-space impact position and normal in the `impacted` signal.
- Headless smoke test and isolated addon test for CI.
- GodotPhysics2D support for the control winches.
- Requires Godot 4.7+ and 120 Hz physics; tuned against Rapier2D 0.36.0.

### Fixed

- `is_conscious()` also verifies that the torso is upright and near the control
  body.
