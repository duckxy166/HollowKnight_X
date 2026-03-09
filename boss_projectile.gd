extends Area2D

## Ice projectile fired by the boss. Can be parried back to damage the boss.

const SPEED: float = 150.0
const LIFETIME: float = 5.0
const DAMAGE: int = 1

# Reflected speed multipliers per boss phase
const REFLECT_SPEED_MULTIPLIERS: Array[float] = [1.5, 1.8, 2.2, 3.0]

var direction: Vector2 = Vector2.LEFT
var reflected: bool = false
var lifetime_timer: float = LIFETIME
var boss_phase: int = 1
var current_speed: float = SPEED

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	add_to_group("enemy_attack")
	anim.play("default")
	# Flip sprite based on direction
	if direction.x > 0:
		anim.flip_h = true
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	position += direction * current_speed * delta

	lifetime_timer -= delta
	if lifetime_timer <= 0:
		queue_free()


func on_parried(player_position: Vector2) -> void:
	if reflected:
		return

	reflected = true
	direction = -direction

	# Flip sprite
	anim.flip_h = not anim.flip_h

	# Switch from enemy_attack to enemy_hurtbox
	remove_from_group("enemy_attack")
	add_to_group("enemy_hurtbox")

	# Change collision: now detectable as enemy_hurtbox, and can detect boss hurtbox
	collision_layer = 16  # bit 5 (so player attack can also hit it)
	collision_mask = 16   # bit 5 (to detect boss hurtbox)

	# Visual feedback - tint the projectile
	anim.modulate = Color(0.5, 1.0, 0.5)

	# Speed up reflected projectile based on boss phase
	var phase_index: int = clampi(boss_phase - 1, 0, REFLECT_SPEED_MULTIPLIERS.size() - 1)
	current_speed = SPEED * REFLECT_SPEED_MULTIPLIERS[phase_index]
	lifetime_timer = LIFETIME


func _on_area_entered(area: Area2D) -> void:
	if reflected and area.is_in_group("enemy_hurtbox"):
		# Hit the boss
		var boss = area.get_parent()
		if boss.has_method("take_damage"):
			boss.take_damage(DAMAGE, global_position)
		queue_free()
