extends State

var hurt_timer: float = 0.0

const HURT_DURATION: float = 0.3


func enter() -> void:
	hurt_timer = HURT_DURATION
	character.play_anim("hurt")
	character.set_invincible(1.0)


func physics_process_state(delta: float) -> void:
	character.apply_gravity(delta)

	# Decelerate knockback
	character.velocity.x = move_toward(character.velocity.x, 0.0, 400.0 * delta)

	hurt_timer -= delta
	if hurt_timer <= 0:
		if character.is_on_floor():
			state_machine.transition_to("ground")
		else:
			state_machine.transition_to("air")
