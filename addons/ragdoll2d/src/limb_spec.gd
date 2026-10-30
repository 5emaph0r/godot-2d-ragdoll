@tool
class_name Ragdoll2DLimbSpec extends Resource
## Everything one body part is made of: its shape, its mass, and two rates that
## say how it behaves.
##
## Tuning here is size-independent. muscle_rate and joint_rate are angular
## frequencies in rad/s, not gains, so the same number means the same response on
## a forearm and on a thigh: [Ragdoll2DLimb] scales them by the limb's own inertia.

## Length of the limb along its own axis, in pixels. Sizes the capsule, and is
## what a child limb's attach_fraction is a fraction of.
@export var length: float = 0.0:
	set(value):
		length = value
		emit_changed()

## Visual thickness of the limb, and the base for the capsule radius. Feeds
## inertia, so it does change how much torque the rates below come out as.
@export var width: float = 0.0:
	set(value):
		width = value
		emit_changed()

## Mass of the RigidBody2D. Drives inertia and how much this limb resists being
## pushed or rotated by joints, gravity and impulses.
@export var mass: float = 0.0:
	set(value):
		mass = value
		emit_changed()

## Where along the parent this limb attaches, as a fraction of the parent's
## length: 0 is the parent's start, 1 its end. This is "where on the parent",
## not "which end of me". That one is join_bottom.
@export var attach_fraction: float = 0.0:
	set(value):
		attach_fraction = value
		emit_changed()

## Friction and bounce for this limb's RigidBody2D.
@export var physics_material: PhysicsMaterial:
	set(value):
		physics_material = value
		emit_changed()

## How fast the limb pulls back to its target angle, in rad/s. A natural
## frequency, not a gain, so doubling it makes the pose four times stiffer on any
## limb. Scaled by the figure's muscle factor, so this term is gone at muscle 0.
## Too low and the limb sags under its own weight.
@export var muscle_rate: float = 0.0:
	set(value):
		muscle_rate = value
		emit_changed()

## Same unit, for the anatomical stop at limit_lower and limit_upper. Separate
## from muscle_rate because anatomy is not muscle: this term always acts at full
## strength, even on a limp figure. A weak joint like an elbow can therefore sit
## far below its muscle rate without its stop going soft.
@export var joint_rate: float = 0.0:
	set(value):
		joint_rate = value
		emit_changed()

## Damping as a fraction of critical, 0…1. At 1 the limb settles as fast as it
## can without passing the target; below 1 it overshoots and rings, around
## 0.5…0.7 for arms, which should swing a little. It changes overshoot only, not
## how hard the joint pulls. Applies to both terms, so a swinging arm also gets a
## slightly springy elbow stop.
@export_range(0.0, 1.0, 0.01) var damping_ratio: float = 1.0:
	set(value):
		damping_ratio = value
		emit_changed()

## Lower bound of the allowed angle relative to the parent, in radians. Enforced
## by the limb's own PD controller, not by PinJoint2D's angular limits.
@export var limit_lower: float = 0.0:
	set(value):
		limit_lower = value
		emit_changed()

## Upper bound, same mechanism. Together the two are what stop the ragdoll
## folding through itself, since self-collision is disabled.
@export var limit_upper: float = 0.0:
	set(value):
		limit_upper = value
		emit_changed()

## Contact impulse above which this limb reports an impact, see
## [signal Ragdoll2DLimb.impacted]. An impulse, so it scales with mass: changing a limb's
## mass means revisiting this.
@export var impact_threshold: float = 1200.0:
	set(value):
		impact_threshold = value
		emit_changed()
