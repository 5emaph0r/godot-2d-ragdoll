@tool
class_name Ragdoll2DFigureType
extends Resource
## Everything that makes one kind of figure: how it walks, how the control body
## holds it, and the ten [Ragdoll2DLimbSpec]s it is built from. Every [Ragdoll2D]
## using this resource picks the same values up, so tuning happens here and not
## per scene.


@export_group("Behavior")

@export var walk_speed: float:
	set(value):
		walk_speed = value
		emit_changed()

@export var jump_speed: float:
	set(value):
		jump_speed = value
		emit_changed()

## Seconds the control body takes to reach full walking speed. A kinematic body
## stepped straight to its target velocity excites every mode of the control
## springs and makes the torso wobble on fast direction changes.
@export var walk_ramp: float = 0.15:
	set(value):
		walk_ramp = value
		emit_changed()


@export_group("Control")

## Natural frequency of the torso in its capsule, in rad/s, the same unit the
## limbs are tuned in. Stiffness is mass * rate^2, so doubling this quadruples
## the pull. Keep it well above what a player can shake the controller at (20 to
## 30 rad/s) and below rate * dt = 2, where the spring goes unstable.
@export var control_rate: float = 60.0:
	set(value):
		control_rate = value
		emit_changed()

## Damping of the control springs, as a fraction of critical. 1 settles without
## overshoot. Only tunes motion along the lines: a [DampedSpringJoint2D] is a
## purely axial strut, so sideways motion is handled by
## [member braced_linear_damp]. Tuned for Rapier; other backends may interpret
## this damping differently.
@export var control_damping_ratio: float = 1.0:
	set(value):
		control_damping_ratio = value
		emit_changed()

## Linear damping on the torso while it is braced, removed while it falls.
## Sideways the torso is stiff for free, since a line under tension resists
## being pulled off its axis, but it is undamped. This adds the missing damping.
@export var braced_linear_damp: float = 25.0:
	set(value):
		braced_linear_damp = value
		emit_changed()

## How fast each winch takes up its own line when the figure stands up, in px/s.
## This decides how fast the figure comes upright: the springs are stiff enough
## that the torso tracks the rest length. Low values look weightless because the
## motion is kinematic.
@export var reel_speed: float = 100.0:
	set(value):
		reel_speed = value
		emit_changed()

@export_group("Crawl")
## Top speed the torso is pushed toward while crawling, in px/s. The force
## chases this velocity and fades out once the torso reaches it.
@export var crawl_speed: float = 40.0:
	set(value):
		crawl_speed = value
		emit_changed()
## How hard the figure crawls, as an acceleration in px/s². Each limb is pushed
## with mass * this, so total shove and ground cost both scale with mass. Flat
## ground at friction 1 costs 980; a 20 degree incline about 1250.
##
## Upper bound: the chase rate is crawl_accel / crawl_speed and rate * dt must
## stay under 2, so at 120 Hz and a top speed of 40 the limit is 9600. Lowering
## crawl_speed moves it down.
@export var crawl_accel: float = 2400.0:
	set(value):
		crawl_accel = value
		emit_changed()
## Muscle tone kept while crawling, 0…1, the value [member Ragdoll2D.muscle]
## fades to on entering the crawl. The standard figure uses 1.0 to hold the crawl
## pose; lower values make the crawl floppier.
@export var crawl_muscle: float = 0.15:
	set(value):
		crawl_muscle = value
		emit_changed()

## Friction of every limb while crawling. Lower friction lets the pose springs
## sweep the folded arms and legs across the floor while the body's weight rests
## on them.
@export_range(0.0, 1.0, 0.01) var crawl_friction: float = 0.2:
	set(value):
		crawl_friction = value
		emit_changed()

@export_group("Body")

@export var head_spec : Ragdoll2DLimbSpec:
	set(value):
		head_spec = value
		emit_changed()

@export var torso_spec : Ragdoll2DLimbSpec:
	set(value):
		torso_spec = value
		emit_changed()

@export var upper_arm_spec : Ragdoll2DLimbSpec:
	set(value):
		upper_arm_spec = value
		emit_changed()

@export var lower_arm_spec : Ragdoll2DLimbSpec:
	set(value):
		lower_arm_spec = value
		emit_changed()

@export var upper_leg_spec : Ragdoll2DLimbSpec:
	set(value):
		upper_leg_spec = value
		emit_changed()

@export var lower_leg_spec : Ragdoll2DLimbSpec:
	set(value):
		lower_leg_spec = value
		emit_changed()
