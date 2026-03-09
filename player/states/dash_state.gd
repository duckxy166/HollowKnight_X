extends State

var dash_timer: float = 0.0


func enter() -> void:
	dash_timer = character.DASH_DURATION
	character.velocity = Vector2(character.dir * character.DASH_SPEED, 0.0)
	character.is_invincible = true
	character.can_dash = false
	character.has_dashed = true
	character.play_anim("dash")
	character.dash_sfx.play()
	character.hero_dash_sfx.play()

	# Visual feedback – tint sprite during dash
	character.anim_sprite.modulate = Color(0.5, 0.8, 1.0, 0.8)

	# Disable collision with boss body (layer 7) so player dashes through
	character.set_collision_mask_value(7, false)


func exit() -> void:
	character.is_invincible = false
	character.anim_sprite.modulate = Color.WHITE

	# Re-enable collision with boss body
	character.set_collision_mask_value(7, true)

	# Kill most momentum on exit for a crisp, HK-like stop
	var input_dir: float = character.get_input_direction()
	if input_dir != 0:
		# If holding a direction, bleed to run speed
		character.velocity.x = input_dir * character.SPEED
	else:
		# If no input, stop quickly
		character.velocity.x *= 0.15


func physics_process_state(delta: float) -> void:
	dash_timer -= delta

	# No gravity during dash – horizontal only
	character.velocity.y = 0.0
	character.velocity.x = character.dir * character.DASH_SPEED

	if dash_timer <= 0:
		if character.is_on_floor():
			state_machine.transition_to("ground")
		else:
			state_machine.transition_to("air")
