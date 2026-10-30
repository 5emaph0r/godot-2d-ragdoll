## One control spring plus the bookkeeping its winch needs.
class_name Ragdoll2DWinch
extends RefCounted
## Godot misbehaves at damping 0, the figure creeps instead of falling
## free. A hair above zero is indistinguishable and well-behaved.
const RELEASED_DAMPING: float = 0.01

var joint: DampedSpringJoint2D
var body_a: PhysicsBody2D
var body_b: PhysicsBody2D
## The end that actually has mass. The other is the kinematic control body.
var moving: RigidBody2D
## Where the joint grabs each body, in that body's own local space. The
## physics server bakes these when the joint is configured and never
## exposes them, so they are mirrored here to measure the line.
var anchor_a: Vector2
var anchor_b: Vector2
## Rest length that holds the torso braced — the value authored in the
## scene. Far below the real anchor distance; that gap IS the bracing.
var taut: float = 1.0
## What the winch is currently paying out.
var rest: float = 1.0
## Held-state settings, written only while engaged.
var stiffness: float = 0.0
var damping: float = 0.0
var brace_damp: float = 0.0

## Current distance between the two anchor points.
func line_length() -> float:
	return body_a.to_global(anchor_a).distance_to(body_b.to_global(anchor_b))

func apply(engaged: bool) -> void:
	# rest_length 0 means "fall back to `length`" in Godot, never "zero".
	joint.rest_length = maxf(rest, 0.01)
	# Releasing switches off BOTH halves of the joint: a damped spring is a
	# spring and a dashpot, and the dashpot resists relative velocity along
	# the line no matter what the rest length says.
	joint.stiffness = stiffness if engaged else 0.0
	joint.damping = damping if engaged else RELEASED_DAMPING
	# The joint is a purely axial strut — it damps nothing sideways, and
	# sideways is stiff anyway because the line is pre-tensioned. This is
	# that missing half. REPLACE so releasing really means zero.
	moving.linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	moving.linear_damp = brace_damp if engaged else 0.0
