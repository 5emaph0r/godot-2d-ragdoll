extends Node2D
## One-take showcase for the ragdoll controller.
##
## The whole course is built from code so the geometry and the scripted beats
## live in one place. Everything is driven by physics ticks and positions, so
## repeated runs follow the same beats.
##
## The camera follows the torso with lag and zooms out for the staircase and the
## final drop. The scene quits itself after the final pose, so Movie Maker ends
## cleanly. Record it with:
##
##     godot --path . --resolution 1920x1080 --fixed-fps 60 \
##         --write-movie recordings/showcase.avi res://demo/showcase.tscn

# --- Course -----------------------------------------------------------------
const START_X := 60.0
const GROUND_Y := 0.0
## The figure's root sits half a capsule above the floor.
const START_Y := GROUND_Y - 64.0

const STAIRS_X := 720.0
## Nine short treads: the loose body clips several of them on the way down and
## lands belly-down with the arms ahead, ready for the crawl.
const STEP_COUNT := 9
const STEP_RUN := 30.0
const STEP_RISE := 34.0
const STAIRS_END_X := STAIRS_X + STEP_COUNT * STEP_RUN
const BOTTOM_Y := 590.0

const TUNNEL_X0 := 1120.0
const TUNNEL_X1 := 1380.0
const TUNNEL_CLEARANCE := 62.0
const TUNNEL_TOP_Y := BOTTOM_Y - TUNNEL_CLEARANCE - 92.0

## The last cliff sits close behind the tunnel: a short run builds enough speed
## for the stumble into the small block on top.
const LEDGE_X := 1700.0
## A small block at the cliff edge. The loose body runs into it and pitches over.
const OBSTACLE_W := 12.0
const OBSTACLE_H := 10.0
## No setback: the body tips over the edge without settling on the cliff top.
const OBSTACLE_GAP := 0.0
const LOWER_Y := 820.0

## The set extends far below the visible surfaces, so no bottom edge can show.
const STAIR_BASE_Y := 1300.0
const LOWER_BASE_Y := 1400.0
const WORLD_LEFT := -700.0
const WORLD_RIGHT := 2700.0
## Small raised lip at the far end of the lower floor.
const LIP_W := 150.0
const LIP_H := 46.0

# --- Direction marks --------------------------------------------------------
## Jump while the figure is still on the flat run before the stairs.
const JUMP_X := 400.0
## Go limp just before the top step.
const LOOSE_AT_STAIRS_X := STAIRS_X - 6.0
## Crawl clear of the tunnel before the figure stands.
const CRAWL_TRIGGER_AFTER_TUNNEL := TUNNEL_X1 + 120.0
## Let go just before the block, so the body hits it already limp and trips.
const LOOSE_AT_LEDGE_X := LEDGE_X - OBSTACLE_GAP - OBSTACLE_W - 15.0

# --- Camera -----------------------------------------------------------------
const ZOOM_NORMAL := 2.15
const ZOOM_STAIRS := 1.38
const ZOOM_LEDGE := 1.55
const CAMERA_X_FOLLOW := 3.2
const CAMERA_Y_FOLLOW := 2.1
const CAMERA_ZOOM_FOLLOW := 2.0
const CAMERA_LOOKAHEAD := 26.0

# --- Showcase tuning --------------------------------------------------------
# Kept here so the clip stays reproducible if the shared figure type changes.
const SHOWCASE_WALK_SPEED := 100.0
const SHOWCASE_JUMP_SPEED := 400.0
const SHOWCASE_CRAWL_SPEED := 40.0
const SHOWCASE_CRAWL_ACCEL := 2400.0

# --- Palette ----------------------------------------------------------------
# The level is monochrome: dark slabs, thin light edges. All colours live here,
# so the whole clip can be re-skinned in one place.
const FLOOR_FILL := Color(0.086, 0.102, 0.153)
const FLOOR_FILL_FLOATING := Color(0.078, 0.092, 0.137)
const BLOCK_FILL := Color(0.118, 0.137, 0.196)
const EDGE_SHADOW := Color(0.145, 0.169, 0.243, 0.95)
const EDGE_LIGHT := Color(0.478, 0.510, 0.729, 0.95)
const ROCK_FILL := Color(0.062, 0.075, 0.114)
const TUNNEL_MOUTH := Color(0.035, 0.043, 0.066, 0.55)
const TUNNEL_EDGE := Color(0.36, 0.40, 0.60, 0.8)
const LABEL_COLOR := Color(0.47, 0.51, 0.69, 0.5)

## Scripted beats of the one-take clip, in order. Each phase waits either for
## the figure to reach a world-space trigger or for a physics-time timeout.
enum Phase {
	INTRO,
	WALK,
	JUMP,
	APPROACH,
	STAIR_FALL,
	CRAWL,
	STAND_AFTER_TUNNEL,
	WALK_TO_LEDGE,
	LEDGE_FALL,
	FINAL_RECOVER,
	DONE,
}

@onready var figure: Ragdoll2D = $Figure
@onready var camera: Camera2D = $Camera

var _stand_label: Label

var _phase: Phase = Phase.INTRO
var _phase_time: float = 0.0
var _camera_focus := Vector2.ZERO
var _camera_zoom: float = ZOOM_NORMAL
var _camera_ready: bool = false
var _stand_attempt_time: float = 0.0
## Seconds spent resting after the final landing, or -1 while still falling.
var _land_time: float = -1.0
## How long the body has been lying still on the bottom floor after the stairs.
var _rest_time: float = 0.0
var _viewport_scale: float = 1.0


func _ready() -> void:
	_setup_viewport()
	_apply_showcase_tuning()
	_build_background()
	_build_level()
	_build_labels()
	_build_hud()
	figure.position = Vector2(START_X, START_Y)
	figure.is_active = true
	figure.set_move_axis(0.0)
	_snap_camera()
	_set_phase(Phase.INTRO)


func _process(delta: float) -> void:
	_update_camera(delta)


func _physics_process(delta: float) -> void:
	_phase_time += delta

	# One phase at a time. Positional triggers keep the beats tied to the level;
	# timeouts only act as safety nets so the clip can never get stuck.
	match _phase:
		Phase.INTRO:
			# Let the title settle before the figure starts walking.
			if _phase_time >= 1.3:
				figure.set_move_axis(1.0)
				_set_phase(Phase.WALK)
		Phase.WALK:
			figure.set_move_axis(1.0)
			if figure.control.global_position.x >= JUMP_X and figure.is_conscious():
				figure.request_jump()
				_set_phase(Phase.JUMP)
		Phase.JUMP:
			figure.set_move_axis(1.0)
			# Wait for the landing, with a timeout in case the feet miss.
			if (_phase_time > 0.9 and figure.is_grounded()) or _phase_time > 1.8:
				_set_phase(Phase.APPROACH)
		Phase.APPROACH:
			figure.set_move_axis(1.0)
			# Go limp just before the top step, so the body tumbles down the
			# stairs.
			if figure.control.global_position.x >= LOOSE_AT_STAIRS_X:
				figure.set_move_axis(0.0)
				figure.let_loose()
				_set_phase(Phase.STAIR_FALL)
		Phase.STAIR_FALL:
			figure.set_move_axis(0.0)
			var settled: bool = _phase_time > 1.2 \
					and figure.torso.global_position.y > BOTTOM_Y - 45.0 \
					and figure.torso.linear_velocity.length() < 45.0
			if settled:
				_rest_time += delta
			else:
				_rest_time = 0.0
			if _rest_time >= 1.0:
				_start_crawl()
			elif _phase_time > 6.0:
				# Safety net: never leave the clip stuck on the stairs.
				push_warning("STAIR_FALL did not settle on the bottom floor; crawling from y=%.1f" % figure.torso.global_position.y)
				_start_crawl()
		Phase.CRAWL:
			figure.set_move_axis(1.0)
			# Stand once the tunnel is behind.
			if figure.torso.global_position.x >= CRAWL_TRIGGER_AFTER_TUNNEL:
				figure.set_move_axis(0.0)
				_try_stand_after_tunnel()
				_set_phase(Phase.STAND_AFTER_TUNNEL)
		Phase.STAND_AFTER_TUNNEL:
			figure.set_move_axis(0.0)
			# Retry the stand-up search until it finds room.
			if _phase_time >= _stand_attempt_time \
					and figure.get_state() != Ragdoll2D.State.STANDING:
				_try_stand_after_tunnel()
				_stand_attempt_time = _phase_time + 0.8
			if figure.get_state() == Ragdoll2D.State.STANDING and figure.is_conscious():
				figure.set_move_axis(1.0)
				_set_phase(Phase.WALK_TO_LEDGE)
			elif _phase_time > 4.0:
				# Last resort: keep going. The walk gate catches up once the
				# winches are taut, or the figure crawls to the ledge.
				figure.set_move_axis(1.0)
				_set_phase(Phase.WALK_TO_LEDGE)
		Phase.WALK_TO_LEDGE:
			figure.set_move_axis(1.0)
			# Let go before the block so the loose body hits it shins-first.
			if figure.control.global_position.x >= LOOSE_AT_LEDGE_X:
				figure.set_move_axis(0.0)
				figure.let_loose()
				_set_phase(Phase.LEDGE_FALL)
			elif _phase_time > 4.0:
				# Safety net: the block must not leave the clip standing at the
				# cliff forever if the loose trigger was never reached.
				push_warning("WALK_TO_LEDGE did not reach the loose trigger; dropping from x=%.1f" % figure.torso.global_position.x)
				figure.set_move_axis(0.0)
				figure.let_loose()
				_set_phase(Phase.LEDGE_FALL)
		Phase.LEDGE_FALL:
			figure.set_move_axis(0.0)
			# Wait until the body has come to rest, then stand up.
			if _land_time < 0.0 and _phase_time > 0.8 \
					and figure.torso.global_position.y > LOWER_Y - 45.0 \
					and figure.torso.linear_velocity.length() < 70.0:
				_land_time = 0.0
			if _land_time >= 0.0:
				_land_time += delta
				if _land_time >= 1.3:
					_land_time = -1.0
					_try_final_stand()
					_set_phase(Phase.FINAL_RECOVER)
			elif _phase_time > 5.0:
				_try_final_stand()
				_set_phase(Phase.FINAL_RECOVER)
		Phase.FINAL_RECOVER:
			figure.set_move_axis(0.0)
			if _phase_time >= _stand_attempt_time \
					and figure.get_state() != Ragdoll2D.State.STANDING:
				_try_final_stand()
				_stand_attempt_time = _phase_time + 0.9
			if figure.get_state() == Ragdoll2D.State.STANDING and figure.is_conscious() \
					and _phase_time >= 1.6:
				_set_phase(Phase.DONE)
			elif _phase_time > 4.0:
				_set_phase(Phase.DONE)
		Phase.DONE:
			# Hold the final pose for a beat, then end the recording.
			if _phase_time >= 1.2:
				get_tree().quit()


## Leaves the tumble behind and starts the steerable crawl to the right.
func _start_crawl() -> void:
	_rest_time = 0.0
	figure.start_crawling(1.0)
	figure.set_move_axis(1.0)
	_set_phase(Phase.CRAWL)


## Resets the timers for the new beat.
func _set_phase(next: Phase) -> void:
	_phase = next
	_phase_time = 0.0
	_stand_attempt_time = 0.0
	_rest_time = 0.0
	if next == Phase.STAND_AFTER_TUNNEL:
		_stand_attempt_time = 0.75
	elif next == Phase.FINAL_RECOVER:
		_stand_attempt_time = 0.8
	if next == Phase.FINAL_RECOVER and _stand_label:
		# Keep "STAND UP" hidden until the body has landed on the lower floor.
		_stand_label.visible = true
		create_tween().tween_property(_stand_label, "modulate:a", 1.0, 0.45)


func _try_stand_after_tunnel() -> void:
	figure.set_standing_pose(0.7)


func _try_final_stand() -> void:
	figure.set_standing_pose(0.8)


# --- Camera -----------------------------------------------------------------

## Place the camera on the figure before the first frame, without follow lag.
func _snap_camera() -> void:
	var focus: Vector2 = figure.torso.center() + Vector2(0.0, -18.0)
	_camera_focus = focus
	_camera_zoom = ZOOM_NORMAL * _viewport_scale
	camera.global_position = _camera_focus
	camera.zoom = Vector2.ONE * _camera_zoom
	_camera_ready = true


## Frame-rate independent exponential follow. The lag keeps fast falls readable.
func _update_camera(delta: float) -> void:
	if not _camera_ready:
		return
	var target: Vector2 = figure.torso.center() + Vector2(0.0, -18.0)
	# A little space in front of the figure, in the direction it is being driven.
	var drive: float = figure.move_axis
	if figure.get_state() == Ragdoll2D.State.RAGDOLL:
		drive = 0.0
	target.x += CAMERA_LOOKAHEAD * drive

	var wx: float = 1.0 - exp(-CAMERA_X_FOLLOW * delta)
	var wy: float = 1.0 - exp(-CAMERA_Y_FOLLOW * delta)
	_camera_focus.x = lerpf(_camera_focus.x, target.x, wx)
	_camera_focus.y = lerpf(_camera_focus.y, target.y, wy)
	camera.global_position = _camera_focus

	var zoom_target: float = _target_zoom() * _viewport_scale
	var wz: float = 1.0 - exp(-CAMERA_ZOOM_FOLLOW * delta)
	_camera_zoom = lerpf(_camera_zoom, zoom_target, wz)
	camera.zoom = Vector2.ONE * _camera_zoom


## Wider framing for the staircase and the final drop, normal framing elsewhere.
func _target_zoom() -> float:
	match _phase:
		Phase.APPROACH, Phase.STAIR_FALL:
			return ZOOM_STAIRS
		Phase.LEDGE_FALL:
			return ZOOM_LEDGE
		Phase.FINAL_RECOVER:
			return lerpf(ZOOM_LEDGE, ZOOM_NORMAL, clampf(_phase_time / 1.5, 0.0, 1.0))
		_:
			return ZOOM_NORMAL


# --- Viewport and figure tuning ---------------------------------------------

func _setup_viewport() -> void:
	# The composition is authored for a 1152x648 viewport. The showcase renders
	# at the native window resolution, so every screen-space value below is
	# multiplied by _viewport_scale to keep the composition identical.
	if DisplayServer.get_name() != "headless":
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var vp := get_viewport().get_visible_rect().size
	_viewport_scale = maxf(vp.x / 1152.0, 0.5)


func _ui(value: float) -> float:
	return value * _viewport_scale


func _apply_showcase_tuning() -> void:
	# Duplicate the stock type so the showcase values do not change the shared
	# resource.
	var type := figure.figure_type.duplicate() as Ragdoll2DFigureType
	type.walk_speed = SHOWCASE_WALK_SPEED
	type.jump_speed = SHOWCASE_JUMP_SPEED
	type.crawl_speed = SHOWCASE_CRAWL_SPEED
	type.crawl_accel = SHOWCASE_CRAWL_ACCEL
	figure.figure_type = type


# --- Level construction -----------------------------------------------------

## Builds the course as one static level: start floor, stairs, tunnel floor,
## tunnel ceiling, cliff block and lower floor. The helpers below keep visual
## polygons and collision shapes separate.
func _build_level() -> void:
	var level := Node2D.new()
	level.name = "Level"
	level.z_index = 0
	add_child(level)

	# Starting floor.
	_add_slab(level,
		PackedVector2Array([Vector2(WORLD_LEFT, GROUND_Y), Vector2(STAIRS_X, GROUND_Y),
			Vector2(STAIRS_X, STAIR_BASE_Y), Vector2(WORLD_LEFT, STAIR_BASE_Y)]),
		PackedVector2Array([Vector2(WORLD_LEFT, GROUND_Y), Vector2(STAIRS_X, GROUND_Y)]))

	# The visual staircase polygon is concave; collision uses one convex box per
	# tread.
	_add_stairs(level)

	# Floor under the tunnel and up to the final ledge.
	_add_slab(level,
		PackedVector2Array([Vector2(STAIRS_END_X, BOTTOM_Y),
			Vector2(LEDGE_X, BOTTOM_Y), Vector2(LEDGE_X, STAIR_BASE_Y),
			Vector2(STAIRS_END_X, STAIR_BASE_Y)]),
		PackedVector2Array([Vector2(STAIRS_END_X, BOTTOM_Y),
			Vector2(LEDGE_X, BOTTOM_Y), Vector2(LEDGE_X, LOWER_Y)]))

	_build_tunnel_backdrop(level)

	# The low passage. The slab floats above the floor: the side-on opening reads
	# as a tunnel and keeps the figure visible while it crawls through.
	_add_slab(level,
		PackedVector2Array([Vector2(TUNNEL_X0, TUNNEL_TOP_Y),
			Vector2(TUNNEL_X1, TUNNEL_TOP_Y), Vector2(TUNNEL_X1, BOTTOM_Y - TUNNEL_CLEARANCE),
			Vector2(TUNNEL_X0, BOTTOM_Y - TUNNEL_CLEARANCE)]),
		PackedVector2Array([Vector2(TUNNEL_X0, TUNNEL_TOP_Y),
			Vector2(TUNNEL_X1, TUNNEL_TOP_Y)]), true)

	# Shadowed tunnel mouth, drawn behind the figure.
	var mouth := Polygon2D.new()
	mouth.polygon = PackedVector2Array([
		Vector2(TUNNEL_X0, BOTTOM_Y - TUNNEL_CLEARANCE),
		Vector2(TUNNEL_X1, BOTTOM_Y - TUNNEL_CLEARANCE),
		Vector2(TUNNEL_X1, BOTTOM_Y), Vector2(TUNNEL_X0, BOTTOM_Y)])
	mouth.color = TUNNEL_MOUTH
	mouth.z_index = -3
	level.add_child(mouth)

	# Highlight the underside of the low ceiling so the passage reads as a
	# tunnel.
	var ceiling_edges := [
		[Vector2(TUNNEL_X0, BOTTOM_Y - TUNNEL_CLEARANCE),
			Vector2(TUNNEL_X1, BOTTOM_Y - TUNNEL_CLEARANCE)],
		[Vector2(TUNNEL_X0, BOTTOM_Y - TUNNEL_CLEARANCE), Vector2(TUNNEL_X0, BOTTOM_Y)],
		[Vector2(TUNNEL_X1, BOTTOM_Y - TUNNEL_CLEARANCE), Vector2(TUNNEL_X1, BOTTOM_Y)],
	]
	for pair in ceiling_edges:
		var line := Line2D.new()
		line.points = PackedVector2Array(pair)
		line.width = 2.0
		line.default_color = TUNNEL_EDGE
		line.z_index = -3
		level.add_child(line)

	# A small block at the edge: the loose body hits it with the shins and pitches
	# over.
	_add_block(level,
		Rect2(Vector2(LEDGE_X - OBSTACLE_GAP - OBSTACLE_W, BOTTOM_Y - OBSTACLE_H),
			Vector2(OBSTACLE_W, OBSTACLE_H)))

	# Final, higher drop.
	_add_slab(level,
		PackedVector2Array([Vector2(LEDGE_X, LOWER_Y), Vector2(WORLD_RIGHT, LOWER_Y),
			Vector2(WORLD_RIGHT, LOWER_BASE_Y), Vector2(LEDGE_X, LOWER_BASE_Y)]),
		PackedVector2Array([Vector2(LEDGE_X, LOWER_Y), Vector2(WORLD_RIGHT, LOWER_Y)]))

	# Subtle raised lip at the end of the lower floor.
	_add_slab(level,
		PackedVector2Array([
			Vector2(WORLD_RIGHT - LIP_W, LOWER_Y - LIP_H),
			Vector2(WORLD_RIGHT, LOWER_Y - LIP_H),
			Vector2(WORLD_RIGHT, LOWER_Y),
			Vector2(WORLD_RIGHT - LIP_W, LOWER_Y)]),
		PackedVector2Array([
			Vector2(WORLD_RIGHT - LIP_W, LOWER_Y - LIP_H),
			Vector2(WORLD_RIGHT, LOWER_Y - LIP_H)]))


## Visual staircase plus one box collider per tread. The boxes carry the
## collision; the polygon provides the fill.
func _add_stairs(parent: Node2D) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)

	var stair_points := PackedVector2Array()
	var top_profile := PackedVector2Array()
	top_profile.append(Vector2(STAIRS_X, GROUND_Y))
	for i in STEP_COUNT:
		var y: float = GROUND_Y + STEP_RISE * (i + 1)
		var x0: float = STAIRS_X + STEP_RUN * i
		var x1: float = x0 + STEP_RUN
		stair_points.append(Vector2(x0, y - STEP_RISE))
		stair_points.append(Vector2(x0, y))
		stair_points.append(Vector2(x1, y))
		top_profile.append(Vector2(x0, y))
		top_profile.append(Vector2(x1, y))

		var block := RectangleShape2D.new()
		block.size = Vector2(STEP_RUN, STAIR_BASE_Y - y)
		var collision := CollisionShape2D.new()
		collision.shape = block
		collision.position = Vector2(x0 + STEP_RUN / 2.0, y + block.size.y / 2.0)
		body.add_child(collision)
	stair_points.append(Vector2(STAIRS_END_X, STAIR_BASE_Y))
	stair_points.append(Vector2(STAIRS_X, STAIR_BASE_Y))
	# Close the bright top edge down the last riser so the deepest step has a
	# visible face.
	top_profile.append(Vector2(STAIRS_END_X, BOTTOM_Y))

	var fill := Polygon2D.new()
	fill.polygon = stair_points
	fill.color = FLOOR_FILL
	fill.z_index = -6
	body.add_child(fill)

	var edge_shadow := Line2D.new()
	edge_shadow.points = top_profile
	edge_shadow.width = 7.0
	edge_shadow.default_color = EDGE_SHADOW
	edge_shadow.joint_mode = Line2D.LINE_JOINT_ROUND
	edge_shadow.begin_cap_mode = Line2D.LINE_CAP_ROUND
	edge_shadow.end_cap_mode = Line2D.LINE_CAP_ROUND
	edge_shadow.z_index = -5
	body.add_child(edge_shadow)

	var edge := Line2D.new()
	edge.points = top_profile
	edge.width = 2.0
	edge.default_color = EDGE_LIGHT
	edge.joint_mode = Line2D.LINE_JOINT_ROUND
	edge.begin_cap_mode = Line2D.LINE_CAP_ROUND
	edge.end_cap_mode = Line2D.LINE_CAP_ROUND
	edge.z_index = -4
	body.add_child(edge)


## One static slab with a fill, a soft lower edge and a bright top line.
## [param floating] darkens the fill for the tunnel ceiling.
func _add_slab(parent: Node2D, body_points: PackedVector2Array,
		top_points: PackedVector2Array, floating: bool = false) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)

	var collision := CollisionPolygon2D.new()
	collision.polygon = body_points
	body.add_child(collision)

	var fill := Polygon2D.new()
	fill.polygon = body_points
	fill.color = FLOOR_FILL_FLOATING if floating else FLOOR_FILL
	fill.z_index = -6
	body.add_child(fill)

	var edge_shadow := Line2D.new()
	edge_shadow.points = top_points
	edge_shadow.width = 7.0
	edge_shadow.default_color = EDGE_SHADOW
	edge_shadow.joint_mode = Line2D.LINE_JOINT_ROUND
	edge_shadow.begin_cap_mode = Line2D.LINE_CAP_ROUND
	edge_shadow.end_cap_mode = Line2D.LINE_CAP_ROUND
	edge_shadow.z_index = -5
	body.add_child(edge_shadow)

	var edge := Line2D.new()
	edge.points = top_points
	edge.width = 2.0
	edge.default_color = EDGE_LIGHT
	edge.joint_mode = Line2D.LINE_JOINT_ROUND
	edge.begin_cap_mode = Line2D.LINE_CAP_ROUND
	edge.end_cap_mode = Line2D.LINE_CAP_ROUND
	edge.z_index = -4
	body.add_child(edge)


## A solid rectangle with a full outline for the cliff-top block, which reads
## as a separate object on the ground.
func _add_block(parent: Node2D, rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)

	var box := RectangleShape2D.new()
	box.size = rect.size
	var collision := CollisionShape2D.new()
	collision.shape = box
	collision.position = rect.get_center()
	body.add_child(collision)

	var points := PackedVector2Array([
		rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
		Vector2(rect.position.x, rect.end.y), rect.position])

	var fill := Polygon2D.new()
	fill.polygon = points
	fill.color = BLOCK_FILL
	fill.z_index = -4
	body.add_child(fill)

	var outline := Line2D.new()
	outline.points = points
	outline.width = 2.0
	outline.default_color = EDGE_LIGHT
	outline.joint_mode = Line2D.LINE_JOINT_ROUND
	outline.begin_cap_mode = Line2D.LINE_CAP_ROUND
	outline.end_cap_mode = Line2D.LINE_CAP_ROUND
	outline.z_index = -3
	body.add_child(outline)


## Visual cut-away hill around the tunnel. The physical ceiling is the floating
## slab added by _build_level().
func _build_tunnel_backdrop(level: Node2D) -> void:
	var rock := ROCK_FILL
	var left := TUNNEL_X0 - 70.0
	var right := TUNNEL_X1 + 70.0
	var cap := Polygon2D.new()
	cap.polygon = PackedVector2Array([
		Vector2(left, TUNNEL_TOP_Y), Vector2(left, 88), Vector2(TUNNEL_X0, 44),
		Vector2(TUNNEL_X1, 44), Vector2(right, 88), Vector2(right, TUNNEL_TOP_Y)])
	cap.color = rock
	cap.z_index = -7
	level.add_child(cap)

	for x0 in [left, TUNNEL_X1]:
		var pillar := Polygon2D.new()
		pillar.polygon = PackedVector2Array([
			Vector2(x0, TUNNEL_TOP_Y), Vector2(x0 + 70.0, TUNNEL_TOP_Y),
			Vector2(x0 + 70.0, BOTTOM_Y), Vector2(x0, BOTTOM_Y)])
		pillar.color = rock
		pillar.z_index = -7
		level.add_child(pillar)


## Screen-space gradient, world-space grid and a few fixed lights. The grid
## gives the delayed follow camera a readable reference.
func _build_background() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Backdrop"
	layer.layer = -10
	add_child(layer)

	var rect := TextureRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.035, 0.043, 0.067))
	gradient.set_color(1, Color(0.082, 0.098, 0.149))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 8
	texture.height = 512
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	layer.add_child(rect)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# World-space grid.
	var grid := Node2D.new()
	grid.name = "Grid"
	grid.z_index = -8
	add_child(grid)
	for x in range(-900, 2900, 120):
		var v := Line2D.new()
		v.points = PackedVector2Array([Vector2(x, -700), Vector2(x, 1250)])
		v.width = 1.6
		v.default_color = Color(0.30, 0.35, 0.52, 0.55)
		grid.add_child(v)
	for y in range(-600, 1250, 120):
		var h := Line2D.new()
		h.points = PackedVector2Array([Vector2(-900, y), Vector2(2900, y)])
		h.width = 1.6
		h.default_color = Color(0.30, 0.35, 0.52, 0.55)
		grid.add_child(h)

	# A few fixed points of light in the background.
	for spot in [Vector2(210, -270), Vector2(440, -330), Vector2(1040, -240),
			Vector2(1520, -300), Vector2(2050, -260), Vector2(2380, -340)]:
		var star := Polygon2D.new()
		star.polygon = _circle_points(spot, 2.0, 10)
		star.color = Color(0.32, 0.36, 0.55, 0.45)
		star.z_index = -7
		add_child(star)


## Chapter captions are world labels, so they pan with the camera. "STAND UP"
## stays hidden until the final beat.
func _build_labels() -> void:
	_add_world_label("RUN", Vector2(210, -118))
	_add_world_label("JUMP", Vector2(470, -178))
	_add_world_label("FALL", Vector2(880, 0))
	_add_world_label("CRAWL", Vector2(TUNNEL_X0 + 25, BOTTOM_Y - TUNNEL_CLEARANCE - 20))
	_stand_label = _add_world_label("STAND UP", Vector2(LEDGE_X + 130, LOWER_Y - 100))
	_stand_label.visible = false
	_stand_label.modulate.a = 0.0


func _add_world_label(text: String, pos: Vector2) -> Label:
	# Low contrast keeps the captions in the set.
	var label := Label.new()
	label.text = text
	label.position = pos
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", LABEL_COLOR)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 2
	add_child(label)
	return label


## Screen-space chrome: title, rule and the physics note.
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	layer.layer = 10
	add_child(layer)

	var root := Control.new()
	root.name = "Root"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Vignette, screen-space: keeps the eye on the figure and sits behind the
	# text so the corners of the HUD stay readable.
	var vignette := TextureRect.new()
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.z_index = -1
	var vgrad := Gradient.new()
	vgrad.set_color(0, Color(0, 0, 0, 0.0))
	vgrad.set_color(1, Color(0, 0, 0, 0.38))
	var vtex := GradientTexture2D.new()
	vtex.gradient = vgrad
	vtex.width = 512
	vtex.height = 512
	vtex.fill = GradientTexture2D.FILL_RADIAL
	vtex.fill_from = Vector2(0.5, 0.5)
	vtex.fill_to = Vector2(1.0, 0.5)
	vignette.texture = vtex
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	root.add_child(vignette)
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var title := Label.new()
	title.name = "Title"
	title.position = Vector2(_ui(62), _ui(46))
	title.text = "RAGDOLL 2D"
	title.add_theme_font_size_override("font_size", int(round(_ui(27))))
	title.add_theme_color_override("font_color", Color(0.87, 0.89, 0.97, 0.92))
	title.add_theme_color_override("font_outline_color", Color(0.02, 0.025, 0.04, 0.85))
	title.add_theme_constant_override("outline_size", maxi(1, int(round(_ui(3)))))
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.position = Vector2(_ui(64), _ui(82))
	subtitle.text = "SHOWCASE"
	subtitle.add_theme_font_size_override("font_size", int(round(_ui(12))))
	subtitle.add_theme_color_override("font_color", Color(0.42, 0.46, 0.62, 0.9))
	subtitle.add_theme_color_override("font_outline_color", Color(0.02, 0.025, 0.04, 0.85))
	subtitle.add_theme_constant_override("outline_size", maxi(1, int(round(_ui(2)))))
	root.add_child(subtitle)

	var rule := ColorRect.new()
	rule.position = Vector2(_ui(64), _ui(108))
	rule.size = Vector2(_ui(300), maxf(1.0, _ui(1)))
	rule.color = Color(0.42, 0.46, 0.62, 0.45)
	root.add_child(rule)

	var hint := Label.new()
	root.add_child(hint)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.offset_left = -_ui(402)
	hint.offset_top = -_ui(80)
	hint.offset_right = -_ui(62)
	hint.offset_bottom = -_ui(50)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.text = "PHYSICS 120 HZ  ·  RAPIER 2D"
	hint.add_theme_font_size_override("font_size", int(round(_ui(11))))
	hint.add_theme_color_override("font_color", Color(0.34, 0.38, 0.52, 0.8))
	hint.add_theme_color_override("font_outline_color", Color(0.02, 0.025, 0.04, 0.85))
	hint.add_theme_constant_override("outline_size", maxi(1, int(round(_ui(2)))))


## Polygon approximation of a circle, used for the small background lights.
func _circle_points(center: Vector2, radius: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in segments:
		var a: float = TAU * float(i) / float(segments)
		points.append(center + Vector2(cos(a), sin(a)) * radius)
	return points
