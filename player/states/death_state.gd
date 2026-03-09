extends State

var death_timer: float = 0.0

func enter() -> void:
	character.velocity = Vector2.ZERO
	character.play_anim("death")
	# Disable collisions so enemies pass through the dead body
	character.collision_layer = 0
	character.collision_mask = 1 # Only collide with floor
	character.hurtbox.set_deferred("monitoring", false)
	character.hurtbox.set_deferred("monitorable", false)
	
	# Start blink effect
	var tween = create_tween()
	tween.set_loops(10) # 10 blinks
	tween.tween_property(character.anim_sprite, "modulate:a", 0.0, 0.05)
	tween.tween_property(character.anim_sprite, "modulate:a", 1.0, 0.05)
	
	tween.finished.connect(func():
		character.anim_sprite.visible = false
		# Show Restart UI via GameManager or emit a signal
		GameManager.player_died.emit()
	)

func physics_process_state(delta: float) -> void:
	character.apply_gravity(delta)
	character.velocity.x = move_toward(character.velocity.x, 0.0, 400.0 * delta)
