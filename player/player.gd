extends CharacterBody2D

# ── Movement ──
const SPEED: float = 130.0
const ACCELERATION: float = 900.0
const FRICTION: float = 800.0

# ── Jump ──
const JUMP_VELOCITY: float = -310.0
const JUMP_VELOCITY_MIN: float = -150.0
const GRAVITY: float = 900.0
const MAX_FALL_SPEED: float = 450.0
const COYOTE_TIME: float = 0.1
const JUMP_BUFFER_TIME: float = 0.1

# ── Dash ──
const DASH_SPEED: float = 320.0
const DASH_DURATION: float = 0.16

# ── Combat ──
const ATTACK_DURATION: float = 0.25
const ATTACK_COOLDOWN: float = 0.35
const PARRY_IFRAMES: float = 0.2
const RECOIL_STRENGTH: float = 200.0

# ── Runtime state ──
var dir: int = 1
var is_invincible: bool = false
var can_dash: bool = true
var has_dashed: bool = false
var is_down_attacking: bool = false
var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0
var attack_cooldown_timer: float = 0.0
var health: int = 5

# ── Stamina ──
const MAX_STAMINA: float = 10.0
const STAMINA_REGEN: float = 3.0   # per second
const STAMINA_ATTACK_COST: float = 1.0
const STAMINA_DASH_COST: float = 2.0
const STAMINA_REGEN_DELAY: float = 1.0 # Wait 1 sec before recharging starts
var stamina: float = MAX_STAMINA
var stamina_delay_timer: float = 0.0

# ── Healing potions ──
const HEAL_AMOUNT: int = 2
const MAX_POTIONS: int = 3
var potions: int = MAX_POTIONS
var is_healing: bool = false

# ── Preloads ──
var slash_vfx_scene: PackedScene = preload("res://vfx/slash_vfx.tscn")
var parry_vfx_scene: PackedScene = preload("res://vfx/parry_vfx.tscn")
var dust_vfx_scene: PackedScene = preload("res://vfx/dust_vfx.tscn")

# ── VFX tracking (prevent overlap) ──
var current_slash_vfx: Node2D = null

# ── Node references ──
@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var slash_sprite: Sprite2D = $AttackSprite
@onready var state_machine: StateMachine = $StateMachine
@onready var attack_hitbox: Area2D = $AttackPivot/AttackHitbox
@onready var attack_pivot: Node2D = $AttackPivot
@onready var hurtbox: Area2D = $Hurtbox
@onready var slash_sfx: AudioStreamPlayer = $SlashSFX
@onready var dash_sfx: AudioStreamPlayer = $DashSFX
@onready var footstep_sfx: AudioStreamPlayer = $FootstepSFX
@onready var hero_dash_sfx: AudioStreamPlayer = $HeroDashSFX
@onready var hit_sfx: AudioStreamPlayer = $HitSFX
@onready var hero_parry_sfx: AudioStreamPlayer = $HeroParrySFX
@onready var damage_sfx: AudioStreamPlayer = $DamageSFX


func _ready() -> void:
	floor_constant_speed = true
	attack_hitbox.monitoring = false
	attack_hitbox.area_entered.connect(_on_attack_hitbox_area_entered)
	hurtbox.area_entered.connect(_on_hurtbox_area_entered)
	update_direction(1)


func _physics_process(delta: float) -> void:
	# Coyote time
	if is_on_floor():
		coyote_timer = COYOTE_TIME
		if has_dashed:
			can_dash = true
			has_dashed = false
	else:
		coyote_timer = max(coyote_timer - delta, 0.0)

	# Jump buffer countdown
	if jump_buffer_timer > 0:
		jump_buffer_timer -= delta

	# Attack cooldown
	if attack_cooldown_timer > 0:
		attack_cooldown_timer -= delta

	# Regen stamina over time, but only after delay
	if stamina_delay_timer > 0:
		stamina_delay_timer -= delta
	elif stamina < MAX_STAMINA:
		stamina = min(stamina + STAMINA_REGEN * delta, MAX_STAMINA)

	move_and_slide()


# ── Animation ──

func play_anim(anim_name: String) -> void:
	if anim_sprite.animation == anim_name and anim_sprite.is_playing():
		return
	anim_sprite.play(anim_name)


# ── Direction ──

func update_direction(new_dir: int) -> void:
	if new_dir == 0:
		return
	dir = new_dir
	anim_sprite.flip_h = (dir == 1)
	slash_sprite.flip_h = (dir == -1)
	slash_sprite.position.x = dir * 24
	attack_pivot.scale.x = dir


func get_input_direction() -> float:
	return Input.get_axis("move_left", "move_right")


# ── Physics helpers ──

func apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = min(velocity.y + GRAVITY * delta, MAX_FALL_SPEED)


# ── VFX ──

func spawn_slash_vfx(attack_type: String = "side") -> void:
	# Kill previous VFX so they never stack
	if is_instance_valid(current_slash_vfx):
		current_slash_vfx.queue_free()

	# Play swipe sound
	slash_sfx.play()

	var vfx = slash_vfx_scene.instantiate()
	if attack_type == "down":
		vfx.position = global_position + Vector2(0, 14)
		vfx.rotation_degrees = 90
	elif attack_type == "up":
		vfx.position = global_position + Vector2(0, -20)
		vfx.rotation_degrees = -90
	else:
		vfx.position = global_position + Vector2(dir * 10, -2)
		if dir == -1:
			vfx.scale.x = -1
	get_parent().add_child(vfx)
	current_slash_vfx = vfx


# ── Invincibility ──

func set_invincible(duration: float) -> void:
	is_invincible = true
	var tween = create_tween()
	tween.set_loops(int(duration / 0.06))
	tween.tween_property(anim_sprite, "modulate:a", 0.2, 0.03)
	tween.tween_property(anim_sprite, "modulate:a", 1.0, 0.03)
	tween.finished.connect(func():
		is_invincible = false
		anim_sprite.modulate.a = 1.0
	)


# ── Damage ──

func take_damage(amount: int, from_position: Vector2) -> void:
	if is_invincible or state_machine.current_state.name.to_lower() == "death":
		return
	health -= amount
	damage_sfx.play()
	var knockback_dir = sign(global_position.x - from_position.x)
	if knockback_dir == 0:
		knockback_dir = -dir
	velocity = Vector2(knockback_dir * 200.0, -150.0)
	
	if health <= 0:
		state_machine.transition_to("death")
	else:
		state_machine.transition_to("hurt")


# ── Hitbox callbacks ──

func _on_attack_hitbox_area_entered(area: Area2D) -> void:
	if area.is_in_group("enemy_attack"):
		_handle_parry(area)
	elif area.is_in_group("enemy_hurtbox"):
		if area.get_parent().has_method("take_damage"):
			area.get_parent().take_damage(1, global_position)
		# Play hit sound
		hit_sfx.play()
		# Light screen shake on normal hit
		GameManager.apply_screen_shake(2.0, 0.08)
		# Pogo bounce on down-attack hit (Hollow Knight style)
		if is_down_attacking:
			velocity.y = JUMP_VELOCITY * 0.5
			can_dash = true
		GameManager.apply_hitstop(0.05)


func _on_hurtbox_area_entered(area: Area2D) -> void:
	if area.is_in_group("enemy_attack"):
		take_damage(1, area.global_position)


func _handle_parry(enemy_area: Area2D) -> void:
	hero_parry_sfx.play()
	GameManager.apply_hitstop(0.08)
	GameManager.apply_recoil(self, enemy_area.global_position, RECOIL_STRENGTH)

	# Big juicy parry feedback (no screen flash, that was too harsh)
	GameManager.apply_screen_shake(6.0, 0.15)

	# Spawn sparks and dust at the contact point
	var contact_pos := (global_position + enemy_area.global_position) / 2.0
	var sparks = parry_vfx_scene.instantiate()
	sparks.global_position = contact_pos
	get_parent().add_child(sparks)
	var dust = dust_vfx_scene.instantiate()
	dust.global_position = contact_pos
	get_parent().add_child(dust)

	var enemy = enemy_area.get_parent()
	var was_boss_parrying_player: bool = false
	if enemy is CharacterBody2D:
		GameManager.apply_recoil(enemy, global_position, RECOIL_STRENGTH)
		# Boss doesn't stagger. Player staggers if they hit the boss's parry stance.
		if enemy.is_in_group("boss") and enemy.state != 8: # 8 is DEATH
			was_boss_parrying_player = true
			# We stagger the player
			state_machine.transition_to("hurt")
	elif enemy.has_method("on_parried"):
		enemy.on_parried(global_position)
	
	if not was_boss_parrying_player:
		set_invincible(PARRY_IFRAMES)
	GameManager.parry_occurred.emit(self, enemy_area)
