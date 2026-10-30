extends Node2D
## Demo scene: feeds the ragdolls and switches the controlled one. Sound and
## blood come from the addon's Ragdoll2DImpactFx child.

@export var controlled_index: int = 1

@onready var rotating_platform: AnimatableBody2D = $StaticBody2D3
@onready var figures: Array[Ragdoll2D] = [$Figure, $Figure2, $Figure3, $Figure4, $Figure5, $Figure6]

var _active_marker: ColorRect


func _ready() -> void:
	controlled_index = clampi(controlled_index, 0, figures.size() - 1)
	_active_marker = ColorRect.new()
	_active_marker.size = Vector2(11, 11)
	_active_marker.color = Color(0.30980393, 0.5764706, 0.30980393, 0.4627451)
	_active_marker.z_index = 10
	_active_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_active_marker)

	figures[controlled_index].is_active = true
	_update_active_marker()


func _physics_process(delta: float) -> void:
	rotating_platform.rotate(0.5 * delta)

	var axis: float = Input.get_axis("move_left", "move_right")
	for i in figures.size():
		figures[i].set_move_axis(axis if i == controlled_index else 0.0)
	if Input.is_action_just_pressed("jump"):
		figures[controlled_index].request_jump()

	_update_active_marker()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reset"):
		get_tree().reload_current_scene()
	if event.is_action_pressed("stand"):
		for figure in figures:
			figure.set_standing_pose(1.0)
	if event.is_action_pressed("loose"):
		for figure in figures:
			figure.let_loose()
	if event.is_action_pressed("next_figure"):
		switch_controlled_figure()


func switch_controlled_figure() -> void:
	figures[controlled_index].is_active = false
	figures[controlled_index].set_move_axis(0.0)
	controlled_index = (controlled_index + 1) % figures.size()
	figures[controlled_index].is_active = true
	_update_active_marker()


func _update_active_marker() -> void:
	var head := figures[controlled_index].head
	_active_marker.global_position = head.global_position + Vector2(-5.5, -36.0)
