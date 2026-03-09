extends State

var attack_timer: float = 0.0
var hitbox_active: bool = false
var is_down_attack: bool = false
var is_up_attack: bool = false

# Default hitbox position (side attack, in front of player)
const SIDE_HITBOX_POS := Vector2(14, 0)
# Down attack hitbox position (below player)
const DOWN_HITBOX_POS := Vector2(0, 16)
# Up attack hitbox position (above player)
const UP_HITBOX_POS := Vector2(0, -20)
# Slash sprite positions
const SIDE_SLASH_POS := Vector2(24, 5)   # abs X, sign applied by dir
const DOWN_SLASH_POS := Vector2(0, 20)


func enter() -> void:
	attack_timer = character.ATTACK_DURATION
	character.attack_cooldown_timer = character.ATTACK_COOLDOWN
	character.stamina -= character.STAMINA_ATTACK_COST
	character.stamina_delay_timer = character.STAMINA_REGEN_DELAY

	# Decide attack type
	is_down_attack = (
		not character.is_on_floor()
		and Input.is_action_pressed("move_down")
	)
	is_up_attack = Input.is_action_pressed("move_up") and not is_down_attack

	character.is_down_attacking = is_down_attack

	if is_down_attack:
		character.play_anim("down_attack")
		# Hitbox below player
		character.attack_hitbox.position = DOWN_HITBOX_POS
		character.spawn_slash_vfx("down")
	elif is_up_attack:
		# Fallback to normal attack anim if up_attack doesn't exist
		character.play_anim("attack")
		# Hitbox above player
		character.attack_hitbox.position = UP_HITBOX_POS
		character.spawn_slash_vfx("up")
	else:
		character.play_anim("attack")
		# Hitbox in front of player
		character.attack_hitbox.position = SIDE_HITBOX_POS
		character.spawn_slash_vfx("side")

	hitbox_active = false
	_activate_hitbox()


func exit() -> void:
	character.attack_hitbox.set_deferred("monitoring", false)
	character.attack_hitbox.set_deferred("monitorable", false)
	character.attack_hitbox.position = SIDE_HITBOX_POS
	character.is_down_attacking = false
	is_up_attack = false
	hitbox_active = false


func physics_process_state(delta: float) -> void:
	character.apply_gravity(delta)

	# Slow down horizontal movement during attack
	character.velocity.x = move_toward(
		character.velocity.x, 0.0,
		character.FRICTION * 0.3 * delta
	)

	# Deactivate hitbox after active frames window (first 40%)
	if hitbox_active and attack_timer < character.ATTACK_DURATION * 0.6:
		character.attack_hitbox.set_deferred("monitoring", false)
		character.attack_hitbox.set_deferred("monitorable", false)
		hitbox_active = false

	attack_timer -= delta
	if attack_timer <= 0:
		if character.is_on_floor():
			state_machine.transition_to("ground")
		else:
			state_machine.transition_to("air")


func _activate_hitbox() -> void:
	character.attack_hitbox.set_deferred("monitoring", true)
	character.attack_hitbox.set_deferred("monitorable", true)
	hitbox_active = true
