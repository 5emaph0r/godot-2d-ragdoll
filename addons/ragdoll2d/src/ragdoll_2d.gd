@tool
class_name Ragdoll2D
extends Node2D
## A stick figure: ten [Ragdoll2DLimb] bodies plus a [CharacterBody2D] that steers them.
##
## Only STANDING is driven by the control body. It walks and the spring joints
## drag the limbs along. CRAWLING and RAGDOLL both disable the control body and
## teleport it into the torso; crawling also uses the steering input and keeps the
## limb pose springs at [member Ragdoll2DFigureType.crawl_muscle]. RAGDOLL fades
## them to zero.
##
## Every pose here is authored facing left. Writing [member Ragdoll2DLimb.facing]
## mirrors the target angles and the joint limits together.
##
## The node does not read the [Input] singleton. Feed it with [method set_move_axis]
## and [method request_jump] from your own input code.

## Emitted when a limb reports a contact hard enough to matter. [param global_pos]
## and [param normal] are in world space. Connect this for custom presentation;
## [Ragdoll2DImpactFx] uses it for sound and blood.
signal impacted(global_pos: Vector2, normal: Vector2, severity: float)

## Emitted whenever [member State] changes.
signal state_changed(state: State)

## GDExtension class name of the reference 2D physics backend.
const RAPIER_SERVER: String = "RapierPhysicsServer2D"
const GODOT_PHYSICS_DAMPING_SCALE: float = 0.2
const BACKEND_WARNING: String = "Ragdoll2D is tuned for Rapier2D 0.36.0 at 120 Hz; behavior on other backends may differ."
static var _backend_warned: bool = false

enum State {
	## On its feet. Control body walks, winches braced, muscles at full.
	STANDING,
	## Collapsed but steerable: a push on every limb plus the crawl pose.
	CRAWLING,
	## Collapsed and inert: pose springs, control joints and input all off.
	RAGDOLL,
}

## Index into [member _base_pose] and [member _pose]. The order has to match
## [member body_parts]: _update_pose() pairs the two up by index. TORSO is only
## in the list to keep that alignment — the torso has no anchor, so [Ragdoll2DLimb] never
## reads its target angle.
enum Part {
	HEAD, TORSO,
	UPPER_ARM_L, UPPER_ARM_R, LOWER_ARM_L, LOWER_ARM_R,
	UPPER_LEG_L, UPPER_LEG_R, LOWER_LEG_L, LOWER_LEG_R,
}

## Lateral reach of the stand-up search, in capsule radii.
const STAND_REACH: float = 1.5
## Probe spacing, in capsule radii. Finer finds narrower gaps, costs more queries.
const STAND_STEP: float = 0.25
## How far below the torso a floor still counts, in capsule heights. Deeper is a
## drop, not a place to stand.
const STAND_DEPTH: float = 3.0
## Clearance above the floor, in pixels. Keeps the probe clear of exact-contact
## hits, so it stays absolute instead of scaling with the figure.
const STAND_LIFT: float = 2.0
## Maximum torso tilt for consciousness, in radians.
const CONSCIOUS_TILT: float = 0.1
## Maximum torso distance from the control body, in pixels.
const CONSCIOUS_REACH: float = 10.0
## Muscle fade time when dropping into a crawl.
const CRAWL_FADE: float = 0.25

## Left is the identity, because that is how every pose here is authored.
const FACING_LEFT: float = 1.0
const FACING_RIGHT: float = -1.0

## Minimum torso tilt before "on its back" means anything, as |sin(rotation)|.
## 0.5 is 30 degrees off upright.
const BACK_TILT: float = 0.5
## Seconds on its back before rolling over. A debounce: a crawl tumbles through
## belly-up all the time.
const ROLL_DELAY: float = 1.0

## The same for the crawl, where one cycle hauls the body a shorter way.
const CRAWL_STRIDE: float = 20.0
## Fraction of top speed at which the swing reaches full amplitude. Below it the
## swing fades out, and that fade is the entire transition between standing and
## walking: no extra state, no tween.
const GAIT_RAMP: float = 0.5

# Swing amplitudes at full gait, in radians, authored facing left like every
# other pose here. Legs lead, arms run half a cycle behind them.
const HIP_SWING: float = 0.30
const KNEE_FOLD: float = 0.5
const ARM_SWING: float = 0.3
const ELBOW_FOLD: float = 0.25
# Crawl equivalents. Smaller, because the crawl pose is already folded up and
# the propulsion comes from _crawl(), not from these.
const REACH_SWING: float = 0.35
const PUSH_SWING: float = 0.3
## Seconds to blend the air pose in and out. Doubles as a debounce: a single tick
## of lost ground contact on a step or a slope barely registers.
const AIR_FADE: float = 0.15
## How fast the torso rights itself while crawling, in rad/s, with its damping
## ratio. Stay under SAFETY * physics_ticks_per_second the way [Ragdoll2DLimb] does —
## 84 rad/s at 120 Hz, 42 at 60.
const CRAWL_LEVEL_RATE: float = 38.0
const CRAWL_LEVEL_DAMP: float = 1.2
## Seconds to fade the levelling in and out with the push that makes it necessary.
const CRAWL_LEVEL_FADE: float = 0.2
## How far below the torso to look for the floor, in torso lengths.
const CRAWL_GROUND_REACH: float = 2.0
## Steepest slope the torso will follow, in radians. Past it the figure keeps a
## flatter attitude instead of trying to lie along a wall.
const CRAWL_MAX_TILT: float = 0.8

@export var figure_type: Ragdoll2DFigureType : set = _set_figure_type
## Whether this figure currently accepts player steering. Purely a gate; the
## ragdoll never reads the [Input] singleton itself.
@export var is_active: bool = false

## How hard the muscles pull, 0…1, passed on to every limb. At 0 the joint limits
## still hold but no pose does.
var muscle: float = 1.0 : set = _set_muscle

## Steering input, -1…1, written by [method set_move_axis]. One physics tick of
## jump intent, consumed by [method request_jump].
var move_axis: float = 0.0
var jump_queued: bool = false

var _state: State = State.STANDING
var _winches: Array[Ragdoll2DWinch] = []
## Set when the control body has just been teleported, cleared a step later.
## A transform jump reads back as a huge implicit velocity, and a dashpot
## switched on in the same step multiplies it by the full damping coefficient.
## So the winch sits out one step and engages against a body at rest.
var _winch_settling: bool = false
## Excluded from the stand-up query: the figure lying in the spot it wants to
## stand in is not an obstruction.
var _own_rids: Array[RID] = []
var _transition_tween: Tween
var _shape: CapsuleShape2D
## Shared friction override, swapped onto the limbs only while crawling.
var _crawl_material: PhysicsMaterial

## What the limbs were last told. Starts at 0.0, which is no facing at all, so
## the guard in _set_facing() cannot swallow the first call.
var _facing: float = 0.0

## Seconds spent continuously on its back while crawling.
var _back_time: float = 0.0

## What the layer stack starts from each tick, indexed by [enum Part]. Written by
## _pose_standing() and _pose_crawling() on a state change, never per tick.
var _base_pose := PackedFloat32Array()
## This tick's composed result, rebuilt from _base_pose in _update_pose().
var _pose := PackedFloat32Array()
## Gait cycle position, 0…TAU. Advanced by ground covered, not by time.
var _phase: float = 0.0
## Ground one gait cycle covers: how far a foot swings is how far the body gets,
## so deriving it here is what keeps the feet from skating at any speed or size.
## Cached, because it only changes with the figure's build.
var _walk_stride: float = 1.0
## How far the air pose has taken over, 0…1. Faded rather than switched, so
## taking off and landing do not snap.
var _air: float = 0.0
## How far the torso levelling has faded in, 0…1. Tied to the crawl push rather
## than to the state, so a figure nobody is steering is left to lie where it
## lands, or to be thrown around.
var _level: float = 0.0

@onready var head: Ragdoll2DLimb = %Head
@onready var torso: Ragdoll2DLimb = %Torso
@onready var upper_arm_l: Ragdoll2DLimb = %UpperArmL
@onready var upper_arm_r: Ragdoll2DLimb = %UpperArmR
@onready var lower_arm_l: Ragdoll2DLimb = %LowerArmL
@onready var lower_arm_r: Ragdoll2DLimb = %LowerArmR
@onready var upper_leg_l: Ragdoll2DLimb = %UpperLegL
@onready var upper_leg_r: Ragdoll2DLimb = %UpperLegR
@onready var lower_leg_l: Ragdoll2DLimb = %LowerLegL
@onready var lower_leg_r: Ragdoll2DLimb = %LowerLegR
@onready var body_parts: Array[Ragdoll2DLimb] = [head, torso, upper_arm_l, upper_arm_r, lower_arm_l, lower_arm_r,
										upper_leg_l, upper_leg_r, lower_leg_l, lower_leg_r]
@onready var control: CharacterBody2D = %Control
@onready var control_joints: Array[DampedSpringJoint2D] = [%HeadJoint, %TorsoJoint]
@onready var collision_shape: CollisionShape2D = %CollisionShape


func _ready() -> void:
	if Engine.is_editor_hint():
		# Re-evaluate the rotation warning when the node is moved or turned in
		# the editor. _get_configuration_warnings() alone does not refresh live.
		set_notify_transform(true)
	if (not Engine.is_editor_hint() and not _backend_warned
			and PhysicsServer2D.get_class() != RAPIER_SERVER):
		_backend_warned = true
		push_warning(BACKEND_WARNING)
	if figure_type == null:
		push_error("Ragdoll2D has no Ragdoll2DFigureType — assign one in the inspector.")
		set_physics_process(false)
		return
	if collision_shape == null || collision_shape.shape is not CapsuleShape2D:
		push_error("Collision shape of CharacterBody has to be a CapsuleShape2D")
		set_physics_process(false)
		return
	_shape = collision_shape.shape
	_load_figure()
	_set_muscle(muscle)
	# Both of these need the specs from _load_figure(): a limb without one has no
	# limits to mirror, and assigning a spec emits layout_changed.
	_set_facing(FACING_LEFT)
	_connect_layout_signals()
	_connect_impact_signals()
	# Sized once; the pose functions below write into them by index.
	_base_pose.resize(body_parts.size())
	_pose.resize(body_parts.size())
	_pose_standing()
	_state = State.STANDING
	_start_transition(0.0, 1.0)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint(): return
	_update_winches(delta)
	match _state:
		State.STANDING:
			_walk(delta)
		State.CRAWLING:
			_follow()
			_right_self(delta)
			_level_torso(delta)
			_crawl()
		State.RAGDOLL:
			_follow()
	_update_pose(delta)
	# One tick of intent. A jump requested in the air is dropped rather than
	# buffered until the next landing.
	jump_queued = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		update_configuration_warnings()


## Feeds steering input without coupling the ragdoll to the [Input] singleton.
## [param axis] is clamped to -1…1; positive is right.
func set_move_axis(axis: float) -> void:
	move_axis = clampf(axis, -1.0, 1.0)


## Requests a jump for the next physics tick. Ignored unless the figure is
## standing, conscious and on the floor.
func request_jump() -> void:
	jump_queued = true


## Pulls the figure upright over [param duration] seconds, 0.0 to snap.
##
## Returns false and starts crawling instead if the upright capsule fits nowhere
## nearby, under a low ceiling or in a tunnel. Nothing is moved to find that out.
## Calling this while already standing only re-applies the pose and skips the
## clearance check.
func set_standing_pose(duration: float) -> bool:
	if not is_node_ready() or _shape == null: return false
	if _state != State.STANDING and not _try_stand_up():
		start_crawling()
		return false
	_pose_standing()
	_set_crawl_friction(false)
	_set_state(State.STANDING)
	_start_transition(duration, 1.0)
	return true


## Collapses, but leaves the figure steerable. [param direction] optionally sets
## which way the crawl pose faces: positive right, negative left. 0 keeps the
## current facing; a figure on its back is rolled face-down.
func start_crawling(direction: float = 0.0) -> void:
	if not is_node_ready() or figure_type == null: return
	# Turn around if we are on our back, so the crawl pose lands face-down.
	if not is_zero_approx(direction):
		_set_facing(FACING_RIGHT if direction > 0.0 else FACING_LEFT)
	elif _is_on_back():
		_set_facing(-_facing)
	_pose_crawling()
	_collapse(State.CRAWLING, figure_type.crawl_muscle, CRAWL_FADE)


## Drops everything at once: muscles off, control joints off, winch released.
func let_loose() -> void:
	if not is_node_ready(): return
	_collapse(State.RAGDOLL, 0.0, 0.0)


func get_state() -> State:
	return _state


func _set_state(value: State) -> void:
	if _state == value: return
	_state = value
	state_changed.emit(value)


## True while at least one foot ray touches terrain. Only meaningful upright.
func is_grounded() -> bool:
	if not is_node_ready(): return false
	return lower_leg_l.is_touching_ground() or lower_leg_r.is_touching_ground()


## True while the figure could hold itself up: standing, with every winch fully
## reeled in, and the torso actually upright and near the control body. Says
## nothing about whose turn it is.
func is_conscious() -> bool:
	if _state != State.STANDING or _winches.is_empty(): return false
	for w in _winches:
		if absf(w.rest - w.taut) > 0.01:
			return false
	if absf(wrapf(torso.global_rotation, -PI, PI)) > CONSCIOUS_TILT: return false
	return torso.global_position.distance_to(control.global_position) <= CONSCIOUS_REACH


## The single gate for player walking input.
func accepts_input() -> bool:
	return is_active and is_conscious()


## The crawl-mode counterpart of [method accepts_input].
func accepts_crawl_input() -> bool:
	return is_active and _state == State.CRAWLING


## Whether the upright capsule fits anywhere nearby. Ask before offering a
## "get up" prompt, but poll it every few frames rather than every tick: it costs
## a handful of physics queries.
func can_stand_up() -> bool:
	if not is_node_ready() or _shape == null: return false
	return _find_stand_spot().is_finite()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if PhysicsServer2D.get_class() != RAPIER_SERVER:
		warnings.append(BACKEND_WARNING)
	if figure_type == null:
		warnings.append("No Ragdoll2DFigureType assigned — no joints will be created.")
	var tick_rate: int = Engine.physics_ticks_per_second
	if tick_rate < 120:
		warnings.append("Physics tick rate is %d Hz. The included tuning was authored at 120 Hz; set physics/common/physics_ticks_per_second=120 or retune the figure." % tick_rate)
	# The controller assumes world-up gravity and an upright stand-up capsule.
	# A rotated node still simulates, but the figure is authored upright and
	# every world-space query below relies on that.
	var world_rotation: float = global_rotation if is_inside_tree() else rotation
	world_rotation = wrapf(world_rotation, -PI, PI)
	if absf(world_rotation) > 0.001:
		warnings.append("Ragdoll2D is rotated by %.1f° in world space. Keep it and its parents unrotated; the controller assumes world-up gravity and an upright stand-up capsule." % rad_to_deg(world_rotation))
	return warnings


func _set_muscle(value: float) -> void:
	muscle = value
	# Safe to call before the node enters the tree; _ready() re-applies it.
	if not is_node_ready(): return
	for part in body_parts:
		part.muscle = muscle


func _load_figure() -> void:
	_apply_figure_type()
	if Engine.is_editor_hint(): return
	_disable_self_collision()
	_build_winches()
	_collect_own_rids()
	_apply_control_tuning()


func _connect_layout_signals() -> void:
	if not Engine.is_editor_hint(): return
	for part in body_parts:
		if not part.layout_changed.is_connected(_place_limbs):
			part.layout_changed.connect(_place_limbs)


func _connect_impact_signals() -> void:
	if Engine.is_editor_hint(): return
	for part in body_parts:
		if not part.impacted.is_connected(_on_limb_impacted):
			part.impacted.connect(_on_limb_impacted)


## Forwards limb impacts to the figure signal. Presentation is handled by
## [Ragdoll2DImpactFx] or by the game.
func _on_limb_impacted(global_pos: Vector2, normal: Vector2, severity: float) -> void:
	impacted.emit(global_pos, normal, severity)


## The figure is drawn from the side, so limbs overlap constantly.
func _disable_self_collision() -> void:
	for i in body_parts.size():
		for j in range(i + 1, body_parts.size()):
			body_parts[i].add_collision_exception_with(body_parts[j])
		body_parts[i].add_collision_exception_with(control)


func _place_limbs() -> void:
	for part in body_parts:
		part.place()


func _create_joints() -> void:
	if Engine.is_editor_hint(): return
	for part in body_parts:
		part.create_joint()


## Rebuilds in GDScript what the physics server bakes into each joint: the two
## anchor points in their bodies' local frames, so the live line length can be
## measured. Godot puts anchor A at the joint origin and anchor B one `length`
## along the joint's local +Y.
func _build_winches() -> void:
	_winches.clear()
	for joint in control_joints:
		var a: PhysicsBody2D = joint.get_node_or_null(joint.node_a) as PhysicsBody2D
		var b: PhysicsBody2D = joint.get_node_or_null(joint.node_b) as PhysicsBody2D
		if a == null or b == null:
			push_error("%s is not connected to two physics bodies." % joint.name)
			continue
		var w := Ragdoll2DWinch.new()
		w.joint = joint
		w.body_a = a
		w.body_b = b
		w.moving = (b as RigidBody2D) if b is RigidBody2D else (a as RigidBody2D)
		if w.moving == null:
			push_error("%s has no RigidBody2D end to pull on." % joint.name)
			continue
		w.anchor_a = a.to_local(joint.global_position)
		w.anchor_b = b.to_local(joint.to_global(Vector2(0, joint.length)))
		# rest_length 0 means "use `length`", so read the effective value.
		w.taut = joint.rest_length if joint.rest_length > 0.0 else joint.length
		w.rest = w.taut
		_winches.append(w)


func _collect_own_rids() -> void:
	_own_rids = [control.get_rid()]
	for part in body_parts:
		_own_rids.append(part.get_rid())


func _apply_control_tuning() -> void:
	if figure_type == null: return
	var rate: float = figure_type.control_rate
	# Rapier's spring damping is force-based, GodotPhysics2D uses a velocity
	# factor, so the critical Rapier value over-damps the winch into a rigid rod.
	# Long-term, replace the springs with a custom force-based resolver.
	var ratio: float = figure_type.control_damping_ratio
	if PhysicsServer2D.get_class() != RAPIER_SERVER:
		ratio *= GODOT_PHYSICS_DAMPING_SCALE
	for w in _winches:
		w.stiffness = w.moving.mass * rate * rate
		w.damping = 2.0 * ratio * w.moving.mass * rate
		w.brace_damp = figure_type.braced_linear_damp


## Engaged: each line reels itself in at reel_speed until it reaches taut.
## Released: follow the real distance, so re-engaging starts from zero stretch.
func _update_winches(delta: float) -> void:
	if figure_type == null: return
	var engaged: bool = _state == State.STANDING and not _winch_settling
	for w in _winches:
		w.rest = move_toward(w.rest, w.taut, figure_type.reel_speed * delta) if engaged else w.line_length()
		w.apply(engaged)
	_winch_settling = false


func _set_figure_type(value: Ragdoll2DFigureType) -> void:
	if figure_type: figure_type.changed.disconnect(_apply_figure_type)
	figure_type = value
	if figure_type: figure_type.changed.connect(_apply_figure_type)
	_apply_figure_type()

func _apply_figure_type() -> void:
	if figure_type == null or not is_node_ready(): return
	head.spec = figure_type.head_spec
	torso.spec = figure_type.torso_spec
	upper_arm_l.spec = figure_type.upper_arm_spec
	upper_arm_r.spec = figure_type.upper_arm_spec
	lower_arm_l.spec = figure_type.lower_arm_spec
	lower_arm_r.spec = figure_type.lower_arm_spec
	upper_leg_l.spec = figure_type.upper_leg_spec
	upper_leg_r.spec = figure_type.upper_leg_spec
	lower_leg_l.spec = figure_type.lower_leg_spec
	lower_leg_r.spec = figure_type.lower_leg_spec
	# Both legs share a spec. The foot sits one leg's length from the hip and
	# sweeps HIP_SWING to either side of it, so one stance covers 2*leg*sin().
	_walk_stride = 4.0 * sin(HIP_SWING) \
			* (figure_type.upper_leg_spec.length + figure_type.lower_leg_spec.length)
	_apply_control_tuning()
	# Limbs before joints: create_joint() pins to the limb's current position.
	_place_limbs()
	_create_joints()
	# A resource change re-applies each limb's spec material; put the crawl
	# override back if the figure is mid-crawl.
	if _crawl_material == null:
		_crawl_material = PhysicsMaterial.new()
	_crawl_material.friction = figure_type.crawl_friction
	_crawl_material.bounce = 0.0
	_set_crawl_friction(_state == State.CRAWLING)


## Swaps the low-friction material in while the pose springs sweep the folded
## limbs across the floor, and restores each limb's spec material afterwards.
func _set_crawl_friction(enabled: bool) -> void:
	if _crawl_material == null: return
	for part in body_parts:
		if part.spec == null: continue
		part.physics_material_override = _crawl_material if enabled else part.spec.physics_material


# --- States -----------------------------------------------------------------


func _pose_standing() -> void:
	_base_pose[Part.HEAD] = 0.0
	_base_pose[Part.UPPER_ARM_L] = -0.25
	_base_pose[Part.UPPER_ARM_R] = 0.25
	_base_pose[Part.LOWER_ARM_L] = 0.2
	_base_pose[Part.LOWER_ARM_R] = 0.2
	_base_pose[Part.UPPER_LEG_L] = -0.2
	_base_pose[Part.UPPER_LEG_R] = 0.3
	_base_pose[Part.LOWER_LEG_L] = -0.1
	_base_pose[Part.LOWER_LEG_R] = -0.1

func _pose_crawling() -> void:
	_base_pose[Part.HEAD] = 1.0
	_base_pose[Part.UPPER_ARM_L] = 2.25
	_base_pose[Part.UPPER_ARM_R] = 2.0
	_base_pose[Part.LOWER_ARM_L] = 1.8
	_base_pose[Part.LOWER_ARM_R] = 1.8
	_base_pose[Part.UPPER_LEG_L] = 2.2
	_base_pose[Part.UPPER_LEG_R] = 2.3
	_base_pose[Part.LOWER_LEG_L] = -2.1
	_base_pose[Part.LOWER_LEG_R] = -2.1

## The only way into a collapsed state. Disabling the control body's collider is
## what makes the unconditional teleport in _follow() safe.
func _collapse(to: State, to_muscle: float, fade: float) -> void:
	# Idempotent: re-entering would restart the fade, so a caller running its
	# state-enter every tick would pin the muscles mid-fade.
	if _state == to: return
	_set_state(to)
	_set_crawl_friction(to == State.CRAWLING)
	control.velocity = Vector2.ZERO
	# Deferred: may be called from inside a physics step.
	collision_shape.set_deferred("disabled", true)
	_start_transition(fade, to_muscle)


## Standing is the only state that walks: the control body drives, the springs
## drag the figure behind it.
func _walk(delta: float) -> void:
	var velocity: Vector2 = control.velocity + control.get_gravity() * delta
	# Only steer on the floor. In the air the current velocity carries on, which
	# is what makes a jump feel like a jump.
	if control.is_on_floor():
		var target_x: float = 0.0
		if accepts_input():
			target_x = move_axis * figure_type.walk_speed
			# Facing follows the input, not the velocity that comes back out of
			# move_and_slide(): a figure knocked backwards should not turn
			# around to watch itself go.
			if not is_zero_approx(target_x):
				_set_facing(FACING_RIGHT if target_x > 0.0 else FACING_LEFT)
			if jump_queued:
				velocity.y = -figure_type.jump_speed
		var accel: float = figure_type.walk_speed / maxf(figure_type.walk_ramp, 0.001)
		velocity.x = move_toward(velocity.x, target_x, accel * delta)
	control.velocity = velocity
	control.move_and_slide()


## Teleports the control body into the torso, with no sweep and no collision
## test: the ragdoll alone decides where the figure ends up. Safe because the
## target sits inside a collider that has already resolved against the world.
func _follow() -> void:
	control.velocity = Vector2.ZERO
	control.global_position = torso.center()

## The crawl input, -1…1, or 0 when nobody is steering this figure. Shared by the
## push in [method _crawl] and the levelling in [method _level_torso], which only
## has a job while something is actually pushing the figure over.
func _crawl_axis() -> float:
	return move_axis if accepts_crawl_input() else 0.0

## One push per limb, scaled by that limb's mass, so the figure pulls itself
## along instead of the torso dragging nine dead weights. It chases a target
## velocity rather than shoving at a constant rate, which gives a top speed
## instead of sliding on ice.
##
## No ground check on purpose, and facing is left alone: mirroring the pose under
## a collapsed figure swings nine slack joints through half a circle and reads as
## a spasm.
func _crawl() -> void:
	var axis: float = _crawl_axis()
	# Without this the velocity term brakes towards zero: no sliding down slopes,
	# and a dead stop in mid-air.
	if is_zero_approx(axis): return
	var target: float = axis * figure_type.crawl_speed
	var cap: float = figure_type.crawl_accel
	var rate: float = cap / maxf(figure_type.crawl_speed, 0.001)
	for part in body_parts:
		var accel: float = clampf((target - part.linear_velocity.x) * rate, -cap, cap)
		part.apply_central_force(Vector2(accel * part.mass, 0.0))

## Rolls the figure back onto its front once it has been upturned long enough
## while being steered. Mirroring the pose is only the request; [method
## _level_torso] is what carries it out, because flipping the facing flips its
## target by half a turn.
##
## Gated on the same push, and that is the whole point. Asking for a roll while
## the levelling is off throws ten slack limbs through a half circle and hopes;
## the torque that comes back tips the torso over again, which asks for another
## roll a moment later. A figure nobody is steering would flip back and forth
## forever, and it has no reason to be doing anything at all.
##
## Since _is_on_back() reads _facing, the timer clears itself on the tick the
## facing flips.
func _right_self(delta: float) -> void:
	if is_zero_approx(_crawl_axis()) or not _is_on_back():
		_back_time = 0.0
		return
	_back_time += delta
	if _back_time < ROLL_DELAY: return
	_back_time = 0.0
	_set_facing(-_facing)

## Holds the torso flat while the crawl is being driven, because nothing else
## does. The push in [method _crawl] acts horizontally through each limb's centre
## while the ground resists from below, and that couple pitches the figure onto
## its face; the torso is also the one limb with no anchor, so it takes every
## other limb's reaction torque with nothing to regulate it.
##
## Gated on the push rather than on the state, and faded in and out with it. A
## figure lying somewhere unsteered has no disturbance to reject, and one that
## keeps straightening itself out reads as alive when it should read as dropped.
## The side effect is that a figure on its back rights itself the moment you
## steer it, which is about when you want it to.
##
## Deliberately one-sided — the reaction torque goes nowhere, so this invents
## angular momentum the same way the control body invents a walk.
func _level_torso(delta: float) -> void:
	var want: float = 0.0 if is_zero_approx(_crawl_axis()) else 1.0
	_level = move_toward(_level, want, delta / CRAWL_LEVEL_FADE)
	if is_zero_approx(_level): return

	var error: float = wrapf(_level_angle() - torso.rotation, -PI, PI)
	var extent: float = torso.spec.length + torso.spec.width
	var iner: float = torso.mass * extent * extent / 12.0
	var stiffness: float = iner * CRAWL_LEVEL_RATE * CRAWL_LEVEL_RATE
	var damping: float = 2.0 * CRAWL_LEVEL_DAMP * iner * CRAWL_LEVEL_RATE
	# Deliberately not Ragdoll2DLimb.pd(): that clamps the P term at SAT_ANGLE so a limb
	# gives way under load, which is the opposite of what a levelling controller
	# wants. Unclamped the restoring torque keeps growing with the error, so there
	# is an equilibrium instead of a threshold the push simply wins past.
	torso.apply_torque((error * stiffness - torso.angular_velocity * damping)
			* muscle * _level)

## The attitude the torso is held at while crawling: lying along the ground, or
## flat where there is no ground under it. Prone facing left is -PI/2 and the
## slope turns the whole figure with it, so the two simply add — the tilt is not
## mirrored, because a hill does not care which way the figure is pointing.
##
## One ray straight down, which is enough for the gentle terrain anything can
## crawl on and costs a single query per tick. Steep hits are clamped rather than
## followed.
func _level_angle() -> float:
	var flat: float = -PI / 2.0 * _facing
	var ray := PhysicsRayQueryParameters2D.new()
	ray.from = torso.center()
	ray.to = ray.from + Vector2(0.0, torso.spec.length * CRAWL_GROUND_REACH)
	ray.exclude = _own_rids
	ray.collision_mask = control.collision_mask
	var hit: Dictionary = control.get_world_2d().direct_space_state.intersect_ray(ray)
	if hit.is_empty(): return flat
	# A floor rotated by t has normal (sin t, -cos t). This reads t back out.
	var normal: Vector2 = hit.normal
	return flat + clampf(atan2(normal.x, -normal.y), -CRAWL_MAX_TILT, CRAWL_MAX_TILT)

## Fades the muscles. The control springs are not part of this; the winch decides
## whether they are on at all.
func _start_transition(duration: float, to_muscle: float) -> void:
	if _transition_tween:
		_transition_tween.kill()
	_transition_tween = create_tween()
	_transition_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_transition_tween.tween_property(self, "muscle", to_muscle, duration)


func _try_stand_up() -> bool:
	var spot: Vector2 = _find_stand_spot()
	if not spot.is_finite(): return false
	control.global_position = spot
	control.velocity = Vector2.ZERO
	# One settling step before the springs come on: `rest` still holds the length
	# from when the control body sat inside the torso, and the teleport spike has
	# to pass with the winch released.
	_winch_settling = true
	collision_shape.disabled = false
	return true


## Looks for somewhere the upright capsule fits, nearest first: above the torso,
## then a step out to each side. Returns the control body's origin for that spot,
## or [constant Vector2.INF] if the figure is boxed in.
##
## Nothing is moved and the shape is never resized. A ray finds the floor, the
## capsule goes to the space state as a query, and the figure's own bodies are
## excluded. Assumes the control body is never rotated.
func _find_stand_spot() -> Vector2:
	var space: PhysicsDirectSpaceState2D = control.get_world_2d().direct_space_state
	var from: Vector2 = torso.center()

	var ray := PhysicsRayQueryParameters2D.new()
	ray.exclude = _own_rids
	ray.collision_mask = control.collision_mask

	var probe := PhysicsShapeQueryParameters2D.new()
	probe.shape = _shape
	probe.exclude = _own_rids
	probe.collision_mask = control.collision_mask

	var step: float = _shape.radius * STAND_STEP
	var steps: int = int(ceilf(STAND_REACH / STAND_STEP))
	var depth: float = _shape.height * STAND_DEPTH

	for i in steps * 2 + 1:
		# 0, +1, -1, +2, -2, … so the nearest free spot wins.
		var out: int = (i + 1) / 2
		var x: float = from.x + (out if i % 2 == 1 else -out) * step
		ray.from = Vector2(x, from.y)
		ray.to = Vector2(x, from.y + depth)
		var floor_hit: Dictionary = space.intersect_ray(ray)
		if floor_hit.is_empty(): continue
		# CapsuleShape2D.height is the full extent, caps included.
		var centre := Vector2(x, floor_hit.position.y - _shape.height / 2.0 - STAND_LIFT)
		probe.transform = Transform2D(0.0, centre)
		if space.intersect_shape(probe, 1).is_empty():
			return centre - collision_shape.position
	return Vector2.INF


## The only writer of [member Ragdoll2DLimb.facing]. Guarded because _walk() calls it
## every tick the figure moves, and re-deriving ten joints' limits for an
## unchanged value is pure waste.
func _set_facing(value: float) -> void:
	if value == _facing: return
	for part in body_parts:
		part.facing = value
	_facing = value

func _is_on_back() -> bool:
	var tilt: float = sin(torso.rotation)
	return absf(tilt) > BACK_TILT and _facing * tilt > 0.0

# --- Pose -------------------------------------------------------------------


## Rebuilds every limb's target angle from the base pose up, then hands the
## result to the limbs. Runs last in the tick, because the gait reads the speed
## the movement code above it just produced.
##
## Layers are applied in call order and each is free to add to or overwrite what
## the ones below it left in [member _pose]. There is only the gait so far;
## anything that later wants a say in how the figure is held — a weapon deciding
## where the arms go, a punch taking over one arm — hooks in between the gait and
## the flush, and takes over by blending at a weight rather than by writing
## directly, so it can fade in instead of popping.
func _update_pose(delta: float) -> void:
	for i in body_parts.size():
		_pose[i] = _base_pose[i]
	_layer_gait(delta)
	_layer_airborne(delta)
	for i in body_parts.size():
		body_parts[i].target_angle = _pose[i]


## Mixes [param angle] into the buffer at [param w]: 0 leaves the limb alone, 1
## takes it over completely, anything between is a partial hand-over.
##
## Plain lerpf(), not lerp_angle(): the short way round the circle runs through
## the wedge the joint cannot reach, which is the same reason [Ragdoll2DLimb] does not
## wrap its pose error either.
func _blend(part: Part, angle: float, w: float) -> void:
	_pose[part] = lerpf(_pose[part], angle, w)


## Advances the gait and lays it over the base pose.
##
## The phase runs on ground covered rather than on time, so a slow walk gets long
## slow steps instead of the same steps with the feet skating, and a figure shoved
## backwards cycles backwards by itself. Speed is measured along the facing, so
## turning around does not reverse the cycle with it.
func _layer_gait(delta: float) -> void:
	var speed: float
	var top: float
	var stride: float
	match _state:
		State.STANDING:
			speed = -control.velocity.x * _facing
			top = figure_type.walk_speed
			stride = _walk_stride
		State.CRAWLING:
			# The control body is parked inside the torso down here, so its
			# velocity says nothing. The torso is what is making ground.
			speed = -torso.linear_velocity.x * _facing
			top = figure_type.crawl_speed
			stride = CRAWL_STRIDE
		_:
			return

	_phase = wrapf(_phase + TAU * speed * delta / maxf(stride, 0.001), 0.0, TAU)
	var amp: float = clampf(absf(speed) / maxf(top * GAIT_RAMP, 0.001), 0.0, 1.0)
	match _state:
		State.STANDING:
			_gait_standing(amp)
		State.CRAWLING:
			_gait_crawling(amp)


## Walking. Legs lead, arms run half a cycle behind them, the way a person
## counter-rotates.
##
## Centred on each pair's average rather than on each limb's own base angle: the
## standing pose is a split stance on purpose, and a cycle running around that
## would read as a permanent limp. Blending at [param amp] keeps the stance intact
## at a standstill and hands over to the symmetric cycle as speed builds.
func _gait_standing(amp: float) -> void:
	var hip: float = _pair_mid(Part.UPPER_LEG_L, Part.UPPER_LEG_R)
	var knee: float = _pair_mid(Part.LOWER_LEG_L, Part.LOWER_LEG_R)
	var shoulder: float = _pair_mid(Part.UPPER_ARM_L, Part.UPPER_ARM_R)
	var elbow: float = _pair_mid(Part.LOWER_ARM_L, Part.LOWER_ARM_R)

	_blend(Part.UPPER_LEG_L, hip + HIP_SWING * sin(_phase), amp)
	_blend(Part.UPPER_LEG_R, hip + HIP_SWING * sin(_phase + PI), amp)
	_blend(Part.LOWER_LEG_L, knee - KNEE_FOLD * _fold(_phase), amp)
	_blend(Part.LOWER_LEG_R, knee - KNEE_FOLD * _fold(_phase + PI), amp)

	_blend(Part.UPPER_ARM_L, shoulder + ARM_SWING * sin(_phase + PI), amp)
	_blend(Part.UPPER_ARM_R, shoulder + ARM_SWING * sin(_phase), amp)
	_blend(Part.LOWER_ARM_L, elbow + ELBOW_FOLD * _fold(_phase + PI), amp)
	_blend(Part.LOWER_ARM_R, elbow + ELBOW_FOLD * _fold(_phase), amp)


## Crawling. Same contralateral pattern, upper limbs only: the knees and elbows
## are already folded flat in the crawl pose and have nowhere left to go.
##
## Cosmetic only. The figure is moved by the forces in [method _crawl]; nothing
## here has to push off anything.
func _gait_crawling(amp: float) -> void:
	var shoulder: float = _pair_mid(Part.UPPER_ARM_L, Part.UPPER_ARM_R)
	var hip: float = _pair_mid(Part.UPPER_LEG_L, Part.UPPER_LEG_R)

	_blend(Part.UPPER_ARM_L, shoulder + REACH_SWING * sin(_phase), amp)
	_blend(Part.UPPER_ARM_R, shoulder + REACH_SWING * sin(_phase + PI), amp)
	_blend(Part.UPPER_LEG_L, hip + PUSH_SWING * sin(_phase + PI), amp)
	_blend(Part.UPPER_LEG_R, hip + PUSH_SWING * sin(_phase), amp)

## Tucks the legs up and brings the arms forward while the figure is off the
## ground, so a jump stops looking like walking through thin air.
##
## Laid over the gait rather than replacing it: the cycle keeps running
## underneath, so touching down resumes the walk mid-stride instead of restarting
## it. First layer here that overrides instead of adding, and the weight is what
## makes the hand-over gradual in both directions.
func _layer_airborne(delta: float) -> void:
	# The control body is the only honest source. A limb's ground ray lifts with
	# every step, and in a collapsed state nothing is walking to begin with.
	var want: float = 0.0 if _state != State.STANDING or control.is_on_floor() else 1.0
	_air = move_toward(_air, want, delta / AIR_FADE)
	if is_zero_approx(_air): return

	# A loose tuck: knees up and folded, arms swinging forward. Staggered left to
	# right so it does not read as a mannequin, and authored facing left like
	# every other pose here.
	_blend(Part.UPPER_ARM_L, 0.7, _air)
	_blend(Part.UPPER_ARM_R, 0.5, _air)
	_blend(Part.LOWER_ARM_L, 0.5, _air)
	_blend(Part.LOWER_ARM_R, 0.4, _air)
	_blend(Part.UPPER_LEG_L, 0.45, _air)
	_blend(Part.UPPER_LEG_R, 0.25, _air)
	_blend(Part.LOWER_LEG_L, -0.9, _air)
	_blend(Part.LOWER_LEG_R, -0.7, _air)

## Middle of a left/right pair in the base pose, which is where a symmetric cycle
## belongs however lopsided the authored stance is.
func _pair_mid(left: Part, right: Part) -> float:
	return (_base_pose[left] + _base_pose[right]) * 0.5


## 0…1, one smooth bump per cycle, peaking at phase 0. Knees and elbows only fold
## one way, so they get this instead of a sine that would hyperextend them for
## half of every cycle. The peak lands mid-swing, where the joint above crosses
## neutral moving forward.
static func _fold(phase: float) -> float:
	return 0.5 + 0.5 * cos(phase)
