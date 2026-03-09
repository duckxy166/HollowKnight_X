extends State

var has_released_jump: bool = false


func enter() -> void:
	has_released_jump = false
	character.play_anim("air")


func physics_process_state(delta: float) -> void:
	character.apply_gravity(delta)

	var input_dir: float = character.get_input_direction()

	# ── Air control (slightly less responsive than ground) ──
	if input_dir != 0:
		character.velocity.x = move_toward(
			character.velocity.x,
			input_dir * character.SPEED,
			character.ACCELERATION * 0.8 * delta
		)
		character.update_direction(int(sign(input_dir)))
	else:
		character.velocity.x = move_toward(
			character.velocity.x, 0.0,
			character.FRICTION * 0.5 * delta
		)

	# ── Variable jump height ──
	if not has_released_jump and Input.is_action_just_released("jump"):
		has_released_jump = true
		if character.velocity.y < character.JUMP_VELOCITY_MIN:
			character.velocity.y = character.JUMP_VELOCITY_MIN

	# ── Coyote time jump ──
	if Input.is_action_just_pressed("jump") and character.coyote_timer > 0:
		character.velocity.y = character.JUMP_VELOCITY
		character.coyote_timer = 0.0
		has_released_jump = false

	# ── Jump buffer ──
	if Input.is_action_just_pressed("jump"):
		character.jump_buffer_timer = character.JUMP_BUFFER_TIME

	# ── Animation ──
	character.play_anim("air")

	# ── Land ──
	if character.is_on_floor():
		state_machine.transition_to("ground")
		return

	# ── Dash (costs stamina) ──
	if Input.is_action_just_pressed("dash") and character.can_dash and character.stamina >= character.STAMINA_DASH_COST:
		state_machine.transition_to("dash")
		return

	# ── Attack (costs stamina) ──
	if Input.is_action_just_pressed("attack") and character.attack_cooldown_timer <= 0 and character.stamina >= character.STAMINA_ATTACK_COST:
		state_machine.transition_to("attack")
		return
