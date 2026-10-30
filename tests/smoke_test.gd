extends Node2D
## Headless smoke test for the addon. Run with:
##
##     godot --headless res://tests/smoke_test.tscn
##
## Exits with code 0 on success and 1 on failure. It exercises the public API:
## pre-ready properties, walking, jumping, crawling, standing up, going limp and
## both signals. It is not a visual test.

const RAGDOLL_SCENE := preload("res://addons/ragdoll2d/scenes/ragdoll_2d.tscn")
const FLOOR_Y := 420.0

var ragdoll: Ragdoll2D
var frame: int = 0
var start_x: float = 0.0
var max_x: float = -INF
var states: Array[int] = []
var impacts: int = 0
var failures: Array[String] = []


func _ready() -> void:
	var floor_body := StaticBody2D.new()
	floor_body.position = Vector2(0, FLOOR_Y)
	var floor_collision := CollisionShape2D.new()
	var floor_shape := RectangleShape2D.new()
	floor_shape.size = Vector2(4000, 40)
	floor_collision.shape = floor_shape
	floor_body.add_child(floor_collision)
	add_child(floor_body)

	ragdoll = RAGDOLL_SCENE.instantiate()
	ragdoll.position = Vector2(0, 330)
	ragdoll.is_active = true
	ragdoll.muscle = 0.5
	ragdoll.state_changed.connect(_on_state_changed)
	ragdoll.impacted.connect(_on_impacted)
	add_child(ragdoll)

	# The test runs in its own process, so lowering the threshold on the shared
	# lower-leg spec only affects this run. It makes the impact signal fire on
	# ordinary walking contacts instead of relying on a lucky hard landing.
	ragdoll.lower_leg_l.spec.impact_threshold = 1.0

	start_x = ragdoll.torso.global_position.x
	_check(is_equal_approx(ragdoll.head.muscle, 0.5), "muscle set before _ready was not applied")


func _physics_process(_delta: float) -> void:
	frame += 1

	match frame:
		120:
			_check(ragdoll.is_grounded(), "figure is not grounded after settling")
			_check(ragdoll.is_conscious(), "figure did not reel its winches in")
			ragdoll.set_move_axis(1.0)
		360:
			ragdoll.set_move_axis(0.0)
			ragdoll.request_jump()
		400:
			_check(not ragdoll.control.is_on_floor(), "jump did not leave the floor")
		480:
			ragdoll.start_crawling()
			ragdoll.set_move_axis(1.0)
		780:
			ragdoll.set_move_axis(0.0)
			_check(ragdoll.set_standing_pose(1.0), "stand-up was rejected on open ground")
		960:
			ragdoll.let_loose()
		1080:
			_check(ragdoll.set_standing_pose(1.0), "second stand-up was rejected")
		1400:
			_finish()

	var x: float = ragdoll.torso.global_position.x
	if is_finite(x):
		max_x = maxf(max_x, x)

	if frame % 120 == 0 and frame < 1400:
		print("frame %4d  state=%d  x=%.1f  grounded=%s" % [
			frame, ragdoll.get_state(), x, ragdoll.is_grounded()])


func _finish() -> void:
	_check(ragdoll.get_state() == Ragdoll2D.State.STANDING, "figure is not standing at the end")
	_check(ragdoll.torso.global_position.is_finite(), "torso position became non-finite")
	_check(absf(ragdoll.torso.rotation) < 0.5, "torso did not end up upright")
	_check(ragdoll.is_conscious(), "figure did not regain consciousness after standing up")
	_check(max_x - start_x > 50.0, "figure did not walk far enough")
	_check(states.has(Ragdoll2D.State.CRAWLING), "crawling state was never emitted")
	_check(states.has(Ragdoll2D.State.RAGDOLL), "ragdoll state was never emitted")
	_check(states.has(Ragdoll2D.State.STANDING), "standing state was never emitted")
	_check(impacts > 0, "impacted signal never fired")

	if failures.is_empty():
		print("smoke test passed")
		get_tree().quit(0)
		return
	for failure in failures:
		printerr("FAIL: " + failure)
	get_tree().quit(1)


func _on_state_changed(state: int) -> void:
	states.append(state)


func _on_impacted(_global_pos: Vector2, _normal: Vector2, _severity: float) -> void:
	impacts += 1


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
