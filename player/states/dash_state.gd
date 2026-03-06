extends State

var dash_timer: float = 0.0


func enter() -> void:
	dash_timer = character.DASH_DURATION
	character.velocity = Vector2(character.dir * character.DASH_SPEED, 0.0)
	character.is_invincible = true
	character.can_dash = false
	character.has_dashed = true
	character.play_anim("dash")
	character.dash_sfx.play() # Original dash sound
	character.hero_dash_sfx.play() # Added hero_dash sound

	# Visual feedback – tint sprite during dash
	character.anim_sprite.modulate = Color(0.5, 0.8, 1.0, 0.8)


func exit() -> void:
	character.is_invincible = false
	character.anim_sprite.modulate = Color.WHITE


func physics_process_state(delta: float) -> void:
	dash_timer -= delta

	# No gravity during dash – horizontal only
	character.velocity.y = 0.0
	character.velocity.x = character.dir * character.DASH_SPEED

	if dash_timer <= 0:
		# Bleed off speed on exit so it doesn't feel jarring
		character.velocity.x *= 0.5
		if character.is_on_floor():
			state_machine.transition_to("ground")
		else:
			state_machine.transition_to("air")

