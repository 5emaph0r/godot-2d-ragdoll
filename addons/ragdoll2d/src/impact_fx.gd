class_name Ragdoll2DImpactFx
extends Node2D
## Audio and blood for a [Ragdoll2D]. Add it as a child of the ragdoll; the
## default scene already includes one. It listens to the parent's
## [signal Ragdoll2D.impacted] signal and stays out of the physics.
##
## Remove this node or disable [member blood_enabled] if your game handles
## presentation itself. The signal is still emitted either way.

## Stream played on every impact. The included audio is synthesized for this
## addon.
@export var sound: AudioStream
## Silence at the front of [member sound], skipped on playback.
@export var sound_lead: float = 0.0
## Stream played when an impact is harder than [member voice_threshold]. The
## included voice is synthesized for this addon.
@export var voice: AudioStream
## Severity above which [member voice] plays, 0…1. Higher values reserve the
## voice for harder impacts.
@export_range(0.0, 1.0, 0.01) var voice_threshold: float = 0.45
## Whether hard impacts spawn blood particles. Enabled by default. Disable it
## when the game handles blood itself.
@export var blood_enabled: bool = true
## Minimum severity for a blood burst, 0…1. Reported impacts start at 0.25;
## raise this to skip light hits.
@export_range(0.0, 1.0, 0.01) var blood_threshold: float = 0.25
## Tint of the blood particles.
@export var blood_color: Color = Color(0.72, 0.025, 0.04)

var _player: AudioStreamPlayer2D
var _voice: AudioStreamPlayer2D
var _blood_texture: Texture2D


func _ready() -> void:
	var ragdoll := get_parent() as Ragdoll2D
	if ragdoll == null:
		push_warning("Ragdoll2DImpactFx has to be a child of a Ragdoll2D.")
		return
	_player = AudioStreamPlayer2D.new()
	_player.name = "Sound"
	add_child(_player)
	_voice = AudioStreamPlayer2D.new()
	_voice.name = "Voice"
	_voice.pitch_scale = randf_range(0.9, 1.1)
	add_child(_voice)
	_blood_texture = _make_blood_texture()
	ragdoll.impacted.connect(_on_impacted)


func _on_impacted(global_pos: Vector2, normal: Vector2, severity: float) -> void:
	# AudioStreamPlayer2D uses its own global position, not the caller's.
	# Move both players from the ragdoll root to the contact point.
	if sound:
		_player.stream = sound
		_player.pitch_scale = randf_range(0.9, 1.1)
		_player.global_position = global_pos
		_player.play(sound_lead)
	if voice and severity > voice_threshold:
		_voice.stream = voice
		_voice.global_position = global_pos
		_voice.play()
	if blood_enabled and severity >= blood_threshold:
		_spawn_blood(global_pos, normal, severity)


func _spawn_blood(global_pos: Vector2, normal: Vector2, severity: float) -> void:
	var particles := CPUParticles2D.new()
	var parent: Node = get_tree().current_scene
	if parent == null:
		parent = get_parent()
	parent.add_child(particles)
	particles.global_position = global_pos
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.lifetime = 0.55
	particles.direction = normal
	particles.spread = 28.0
	particles.amount = int(lerpf(6.0, 28.0, severity))
	particles.initial_velocity_min = lerpf(80.0, 200.0, severity)
	particles.initial_velocity_max = lerpf(200.0, 620.0, severity)
	particles.gravity = Vector2(0.0, 600.0)
	particles.scale_amount_min = lerpf(0.09, 0.14, severity)
	particles.scale_amount_max = lerpf(0.24, 0.38, severity)
	particles.color = blood_color
	particles.texture = _blood_texture
	particles.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	particles.z_index = 5
	particles.finished.connect(particles.queue_free)
	particles.emitting = true


## A soft round droplet texture for the blood particles.
func _make_blood_texture() -> Texture2D:
	const SIZE := 32
	var image := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var center := (SIZE - 1) * 0.5
	for y in SIZE:
		for x in SIZE:
			var distance := Vector2(x - center, y - center).length() / (SIZE * 0.5)
			var alpha := 1.0 - smoothstep(0.72, 1.0, distance)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)
