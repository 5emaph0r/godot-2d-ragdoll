# Ragdoll 2D

![Ragdoll 2D icon](icon.svg)

Procedural 2D humanoid ragdoll controller for Godot 4. No skeleton and no
animation clips: ten physics bodies, a kinematic control body and PD pose
controllers.

## Install

Copy this folder into your project's `addons/` directory. No editor plugin needs
to be enabled.

## Use

```gdscript
var ragdoll: Ragdoll2D = preload("res://addons/ragdoll2d/scenes/ragdoll_2d.tscn").instantiate()
add_child(ragdoll)
ragdoll.is_active = true

# Feed input yourself; the ragdoll never reads the Input singleton.
ragdoll.set_move_axis(Input.get_axis("move_left", "move_right"))
if Input.is_action_just_pressed("jump"):
    ragdoll.request_jump()

ragdoll.impacted.connect(_on_impact)
```

## Requirements

- Godot 4.7+
- **120 Hz physics** (`physics/common/physics_ticks_per_second=120`); the
  included tuning was authored at 120 Hz
- **Rapier2D 0.36.0** is the backend the included tuning was authored against;
  it is not bundled. Download `godot-rapier-2d-single.zip` from that
  [release](https://github.com/appsinacup/godot-rapier-physics/releases/tag/v0.36.0),
  extract its `addons/godot-rapier2d/` folder into your project, restart the
  editor and select `Rapier2D` under Project Settings > Physics > 2D > Physics
  Engine.
- Other physics backends work, but behavior may differ, especially for the
  stand-up search
- Keep the ragdoll and its parents unrotated in world space; the controller
  assumes world-up gravity and an upright stand-up capsule

## API

`Ragdoll2D`:

- `set_move_axis(axis)`, `request_jump()`
- `set_standing_pose(duration) -> bool`, `start_crawling(direction: float = 0.0)`, `let_loose()`
- `get_state()`, `is_grounded()`, `is_conscious()`, `can_stand_up()`
- signals: `impacted(global_pos, normal, severity)` (world-space), `state_changed(state)`

`Ragdoll2DFigureType` and `Ragdoll2DLimbSpec` hold the body layout and tuning.

## Impact effects

The ragdoll scene includes an `ImpactFx` child (`Ragdoll2DImpactFx`). It plays
impact and voice sounds and spawns blood at the contact point. Streams,
thresholds and blood appearance are exported properties, and blood can be
disabled. Remove the node to handle presentation yourself; the `impacted` signal
is emitted either way. Both included sounds are synthesized for this addon.

## License

MIT. See `LICENSE` next to this file.
