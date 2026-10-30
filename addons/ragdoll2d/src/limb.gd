@tool
class_name Ragdoll2DLimb
extends RigidBody2D
## One body part of a figure: a capsule collider plus its [Line2D] graphics, both
## derived from a shared [Ragdoll2DLimbSpec].
##
## The origin (0,0) is this limb's own joint and the body runs along local +Y;
## [member join_bottom] mirrors that to -Y for the head. [member Ragdoll2DLimbSpec.length]
## is the distance between the two joint points, not the visible extent: the
## round caps overhang by width/2 at each end, so neighbouring limbs merge
## without a gap at a bent joint.
##
## Every limb owns one joint, its upper one, and regulates its angle against the
## limb it is attached to. The figure only writes [member target_angle],
## [member muscle] and [member facing]. Specs are tuned in rad/s; the gains
## behind them are derived once per spec change in _cache_gains(), never per tick.

signal layout_changed

## Emitted on a contact hard enough to matter. [param strength] runs 0…1,
## measured against [member Ragdoll2DLimbSpec.impact_threshold] and
## [constant IMPACT_FULL]. [param normal] is the contact normal in world space.
signal impacted(global_pos: Vector2, normal: Vector2, strength: float)

## Error at which a term reaches full torque, in radians. The P response is
## linear up to here and flat beyond, so the clamp only bites once something has
## thrown the limb far off pose. Lower makes limbs give way sooner under load.
const SAT_ANGLE: float = 0.5

## Ceiling on rate * dt, above which explicit damping stops being stable. Each
## tick the damping term multiplies the relative rate by
## (1 - 2 * ratio * rate * dt), which stops shrinking it once ratio * rate * dt
## reaches 1. Measured on the lower leg at 120 Hz (mass 0.5, length 16, width 5,
## ratio 1): 0.68 stable, 0.91 borderline, 1.13 unstable. This keeps the last
## stable measurement.
##
## It bounds each term on its own, and the pose and limit terms add. That is why
## a permanently firing limit term (a zero-width or inverted arc) shows up as
## fast jitter rather than as a merely wrong pose.
const SAFETY: float = 0.7

## Impulse at which an impact counts as fully severe, as a multiple of the spec's
## threshold. Only shapes how fast severity ramps up.
const IMPACT_FULL: float = 4.0
## Ticks of silence after a reported impact, so one landing spread over several
## solver steps does not fire several times.
const IMPACT_COOLDOWN: int = 8

@export var spec: Ragdoll2DLimbSpec : set = _set_spec
## Setup only, not safe at runtime.
@export var attached_to: NodePath : set = _set_attached_to
@export var join_bottom: bool = false : set = _set_join_bottom
@export var has_ground_ray: bool = false : set = _set_has_ground_ray

var target_angle: float = 0.0
var muscle: float = 1.0

## 1.0 for the pose as authored, -1.0 for its mirror image.
##
## Mirroring a figure drawn from the side negates every angle, so this is a plain
## factor on [member target_angle]. The same write folds it into the joint limits
## via _apply_limits(), so a pose and the stop meant to contain it can never
## disagree about which way the limb faces.
var facing: float = 1.0 : set = _set_facing

var _joint: PinJoint2D
var _anchor: Ragdoll2DLimb

# Gains derived from the spec, cached by _cache_gains(). Pose term:
var _muscle_stiffness: float = 0.0
var _muscle_damping: float = 0.0
var _muscle_torque: float = 0.0
# Anatomical stop, derived independently so a weak joint keeps a solid limit:
var _joint_stiffness: float = 0.0
var _joint_damping: float = 0.0
var _joint_torque: float = 0.0

var _impact_cooldown: int = 0

## The allowed arc for the current facing, as middle plus half-width instead of
## two bounds. Same information as [member Ragdoll2DLimbSpec.limit_lower] and
## [member Ragdoll2DLimbSpec.limit_upper], in the form the controller needs.
##
## Subtracting the middle before wrapping puts the ±PI seam inside the wedge this
## joint can never reach, which leaves the arc symmetric around zero. That is
## what makes a linear clamp correct here: clampf() pushes toward the nearer
## bound as a number, which on a circle is only the nearer bound in fact when the
## arc is centred. Off-centre, and every anatomical joint is, a limb thrown past
## a stop gets driven the long way round until the pose term cancels it and it
## locks there.
##
## Assumes an arc narrower than 2*PI. A wider one just never clamps.
var _limit_mid: float = 0.0
var _limit_half: float = 0.0

@onready var stroke: Line2D = $Stroke
@onready var outline: Line2D = $Outline
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var ground_ray: RayCast2D = $GroundRay


func _ready() -> void:
	_update_anchor()
	_apply_spec()
	_apply_ground_ray()


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint(): return
	if _anchor == null or spec == null: return  # the torso has nothing to regulate against

	# Measured from the middle of the allowed arc rather than from zero, so the
	# wrap seam lands where the joint cannot go (see _limit_mid). Both terms
	# below share this coordinate, which keeps them from fighting each other.
	var angle: float = wrapf(rotation - _anchor.rotation - _limit_mid, -PI, PI)
	# _limit_mid is a constant offset, so it drops out of the derivative.
	var rate: float = angular_velocity - _anchor.angular_velocity

	# --- Pose term: pulls toward target_angle, scaled by muscle. ---
	# Clamped into the arc, because a pose asking for an angle the joint cannot
	# reach would be a standoff for as long as it is held.
	var target: float = clampf(wrapf(target_angle * facing - _limit_mid, -PI, PI), -_limit_half, _limit_half)
	# Deliberately no wrapf on the difference. The shortest way round the circle
	# runs through the wedge and, with self-collision off, straight through the
	# torso. Plain subtraction gives the shortest way through the space the joint
	# can actually travel, which is where the limit term pushes too.
	var torque: float = pd(target - angle, rate, _muscle_stiffness, _muscle_damping, _muscle_torque) * muscle

	# --- Limit term: anatomical stop. Always full strength, never scaled by muscle. ---
	var excess: float = clampf(angle, -_limit_half, _limit_half) - angle
	if not is_zero_approx(excess):
		torque += pd(excess, rate, _joint_stiffness, _joint_damping, _joint_torque)

	# Actio/reactio: the exact opposite goes to the parent.
	apply_torque(torque)
	_anchor.apply_torque(-torque)


## Creates this limb's pin joint, parented to the figure, so every limb sets up
## its own attachment.
func create_joint() -> void:
	if _anchor == null: return
	if !_joint:
		var j := PinJoint2D.new()
		get_parent().add_child(j)
		_joint = j
	_joint.global_position = global_position
	_joint.node_a = _anchor.get_path()
	_joint.node_b = get_path()


func place() -> void:
	if _anchor == null or _anchor.spec == null or spec == null: return
	_anchor.place()
	position = _anchor.position + Vector2(0, _anchor.spec.length * spec.attach_fraction)


## PD controller helper. [param max_force] clamps the P term only; the damping
## term is added afterwards and is deliberately uncapped. Clamping the sum would
## cut the damping away exactly at saturation, when a limb thrown far off pose
## needs it most, turning a large correction into jitter. Damping can only take
## energy out, so uncapped is safe here. Numerical stability is what
## [constant SAFETY] is for.
static func pd(error: float, rate: float, stiffness: float, damping: float, max_force: float) -> float:
	return clampf(error * stiffness, -max_force, max_force) - rate * damping


func is_touching_ground() -> bool:
	return has_ground_ray and ground_ray.is_colliding()

## Centre of this limb's collider in world space. The origin sits at the joint,
## not in the middle of the body, so this is what to aim at when something wants
## "where the limb actually is".
func center() -> Vector2:
	return to_global(collision_shape.position)

func _set_spec(value: Ragdoll2DLimbSpec) -> void:
	if spec: spec.changed.disconnect(_apply_spec)
	spec = value
	if spec: spec.changed.connect(_apply_spec)
	_apply_spec()


func _set_attached_to(value: NodePath) -> void:
	attached_to = value
	_update_anchor()
	layout_changed.emit()


func _set_join_bottom(value: bool) -> void:
	join_bottom = value
	_apply_spec()


func _set_has_ground_ray(value: bool) -> void:
	has_ground_ray = value
	_apply_ground_ray()


func _apply_spec() -> void:
	if spec == null or not is_node_ready(): return
	# join_bottom mirrors the limb: joint stays at the origin, body runs to -Y.
	var dir: float = -1.0 if join_bottom else 1.0
	# A mirrored limb sits flush on its joint instead of overhanging it, so the
	# head rests on the neck rather than straddling it.
	var inset: float = spec.width / 2 if join_bottom else 0.0
	# Line2D needs two distinct points. At length 0 the limb collapses to a dot
	# with round caps, a perfect circle of diameter `width`. That is the head.
	var far: float = inset + maxf(spec.length, 0.01)
	var tip := Vector2(0, dir * far)
	stroke.points = PackedVector2Array([Vector2(0, dir * inset), tip])
	outline.points = stroke.points
	collision_shape.position = Vector2(0, dir * (inset + spec.length / 2))
	ground_ray.position = tip

	stroke.width = spec.width
	outline.width = stroke.width + 1

	var capsule: CapsuleShape2D = collision_shape.shape
	capsule.radius = spec.width / 2
	capsule.height = spec.length + spec.width
	mass = spec.mass
	physics_material_override = spec.physics_material

	# The facing setter is the only other writer of the arc, and it only fires on
	# a change. Without this call a limb that never turns around keeps an arc of
	# zero width, and the limit term pins it at full, unmuscled strength.
	_apply_limits()
	_cache_gains()
	layout_changed.emit()


## Turns the spec's two rates into the six numbers the controller runs on.
## Inertia is a thin-rod approximation over the capsule's full extent. It only
## scales gains, so being a constant factor off the true capsule value is
## harmless as long as it is the same factor everywhere, and [constant SAFETY]
## was calibrated with it.
func _cache_gains() -> void:
	var extent: float = spec.length + spec.width
	var iner: float = spec.mass * extent * extent / 12.0
	var ceiling: float = SAFETY * Engine.physics_ticks_per_second

	var w: float = _checked_rate(spec.muscle_rate, ceiling, "muscle_rate")
	_muscle_stiffness = iner * w * w
	_muscle_damping = 2.0 * spec.damping_ratio * iner * w
	_muscle_torque = _muscle_stiffness * SAT_ANGLE

	w = _checked_rate(spec.joint_rate, ceiling, "joint_rate")
	_joint_stiffness = iner * w * w
	_joint_damping = 2.0 * spec.damping_ratio * iner * w
	_joint_torque = _joint_stiffness * SAT_ANGLE


## Rates above the ceiling are capped, which would otherwise look like a limb
## that quietly refuses to get any stiffer.
func _checked_rate(rate: float, ceiling: float, field: String) -> float:
	if rate <= ceiling: return rate
	push_warning("%s: %s is %.1f rad/s, above the stable ceiling of %.1f rad/s at %d Hz — clamped." % [
		name, field, rate, ceiling, Engine.physics_ticks_per_second])
	return ceiling


func _apply_ground_ray() -> void:
	if is_node_ready():
		ground_ray.enabled = has_ground_ray
		ground_ray.visible = has_ground_ray


func _update_anchor() -> void:
	_anchor = null
	if not attached_to.is_empty():
		_anchor = get_node_or_null(attached_to) as Ragdoll2DLimb

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if Engine.is_editor_hint() or spec == null: return
	if _impact_cooldown > 0:
		_impact_cooldown -= 1
		return
	# Hardest contact of the tick only: a capsule on flat ground reports two
	# points for what is physically one impact.
	var peak: float = 0.0
	var peak_pos: Vector2
	var peak_normal: Vector2
	for i in state.get_contact_count():
		var impulse: float = state.get_contact_impulse(i).length()
		if impulse > peak:
			peak = impulse
			# Both getters say "local", but PhysicsDirectBodyState2D reports
			# these contact coordinates in world space (verified with Rapier2D).
			peak_pos = state.get_contact_local_position(i)
			peak_normal = state.get_contact_local_normal(i)
	if peak >= spec.impact_threshold:
		_impact_cooldown = IMPACT_COOLDOWN
		# Plain division, so the weakest qualifying hit still lands at
		# 1/IMPACT_FULL rather than at zero.
		var severity: float = minf(peak / (spec.impact_threshold * IMPACT_FULL), 1.0)
		# Deferred: this runs inside the physics step, where the tree is locked.
		impacted.emit.call_deferred(peak_pos, peak_normal, severity)

func _set_facing(value: float) -> void:
	facing = value
	_apply_limits()


## Derives the arc the controller runs on, for the current facing.
##
## Mirroring negates angles, so limit_lower … limit_upper maps to
## [-limit_upper, -limit_lower]: swapped as well as negated. Middle and
## half-width sidestep that, since the middle is the average either way round and
## the half-width is an absolute value. The inverted interval a bare swap
## produces cannot be built here at all, which matters: clampf() with its bounds
## reversed returns the lower one from both sides, and every joint would pin to a
## single angle at full strength.
func _apply_limits() -> void:
	if spec == null: return
	var a: float = facing * spec.limit_lower
	var b: float = facing * spec.limit_upper
	_limit_mid = (a + b) * 0.5
	_limit_half = absf(b - a) * 0.5
