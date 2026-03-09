extends Node

## Global game manager - handles hitstop, parry effects, and game state.

@warning_ignore("unused_signal")  # emitted from player.gd, not here
signal parry_occurred(player_node: Node2D, enemy_area: Area2D)

## Emitted when the player's death animation finishes and the restart UI should appear
signal player_died


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Freeze the game for [param duration] seconds (hitstop effect).
## Uses ignore_time_scale timer so it works even at time_scale 0.
func apply_hitstop(duration: float = 0.07) -> void:
	Engine.time_scale = 0.0
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0


## Push [param body] away from [param from_position].
func apply_recoil(body: CharacterBody2D, from_position: Vector2, strength: float = 200.0) -> void:
	var dir = sign(body.global_position.x - from_position.x)
	if dir == 0:
		dir = 1
	body.velocity.x = dir * strength
	body.velocity.y = -strength * 0.5


## Shake the camera for [param duration] seconds with [param intensity] pixels of offset.
## Heavier attacks should use higher intensity (e.g. parry=6, normal hit=2).
func apply_screen_shake(intensity: float = 4.0, duration: float = 0.12) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var original_offset := cam.offset
	var tween := create_tween()
	# Rapid random offsets that decay over time
	var steps := int(duration / 0.02)
	for i in steps:
		var decay := 1.0 - (float(i) / float(steps))
		var shake_x := randf_range(-intensity, intensity) * decay
		var shake_y := randf_range(-intensity, intensity) * decay
		tween.tween_property(cam, "offset", original_offset + Vector2(shake_x, shake_y), 0.02)
	# Snap back to original
	tween.tween_property(cam, "offset", original_offset, 0.02)


## Brief white flash overlay – sells the impact of a parry.
func apply_screen_flash(duration: float = 0.08) -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 100  # On top of everything
	var rect := ColorRect.new()
	rect.color = Color(1.0, 1.0, 1.0, 0.6)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(rect)
	get_tree().root.add_child(canvas)
	# Fade out and self-destruct
	var tween := create_tween()
	tween.tween_property(rect, "color:a", 0.0, duration)
	tween.finished.connect(func(): canvas.queue_free())
