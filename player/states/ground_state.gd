extends State


func enter() -> void:
	character.play_anim("idle")


func physics_process_state(delta: float) -> void:
	character.apply_gravity(delta)

	var input_dir: float = character.get_input_direction()

	# ── Horizontal movement with accel / decel ──
	if input_dir != 0:
		character.velocity.x = move_toward(
			character.velocity.x,
			input_dir * character.SPEED,
			character.ACCELERATION * delta
		)
		character.update_direction(int(sign(input_dir)))
		character.play_anim("run")
		
		# Play footstep sound if not already playing
		if not character.footstep_sfx.playing:
			# Randomize pitch slightly for variation
			character.footstep_sfx.pitch_scale = randf_range(0.9, 1.1)
			character.footstep_sfx.play()
	else:
		character.velocity.x = move_toward(
			character.velocity.x, 0.0,
			character.FRICTION * delta
		)
		character.play_anim("idle")
		character.footstep_sfx.stop()

	# ── Jump (also consumes jump buffer) ──
	if Input.is_action_just_pressed("jump") or character.jump_buffer_timer > 0:
		if character.is_on_floor() or character.coyote_timer > 0:
			character.velocity.y = character.JUMP_VELOCITY
			character.jump_buffer_timer = 0.0
			character.coyote_timer = 0.0
			state_machine.transition_to("air")
			return

	# ── Fell off edge ──
	if not character.is_on_floor():
		state_machine.transition_to("air")
		return

	# ── Dash (costs stamina) ──
	if Input.is_action_just_pressed("dash") and character.can_dash and character.stamina >= character.STAMINA_DASH_COST:
		state_machine.transition_to("dash")
		return

	# ── Attack (costs stamina) ──
	if Input.is_action_just_pressed("attack") and character.attack_cooldown_timer <= 0 and character.stamina >= character.STAMINA_ATTACK_COST:
		state_machine.transition_to("attack")
		return

	# ── Heal (E key, uses a potion) ──
	if Input.is_action_just_pressed("heal") and character.potions > 0 and character.health < 5:
		character.potions -= 1
		character.health = min(character.health + character.HEAL_AMOUNT, 5)
