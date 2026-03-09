extends Area2D

## Lightning strike that telegraphs, then damages the player.
## Spawned by the boss during LIGHTNING state.

const DAMAGE: int = 1
const TELEGRAPH_DURATION: float = 0.6
const STRIKE_FPS: float = 20.0
const TOTAL_FRAMES: int = 13

var textures: Array[Texture2D] = []
var current_frame: int = 0
var frame_timer: float = 0.0
var is_striking: bool = false
var telegraph_timer: float = TELEGRAPH_DURATION

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var telegraph_line: Line2D = $TelegraphLine


func _ready() -> void:
	add_to_group("enemy_attack")
	# Load lightning frames
	for i in range(1, TOTAL_FRAMES + 1):
		textures.append(load("res://asset/VFX/lightning/lightning/lightning_v2_%d.png" % i))

	# Start with telegraph only, no hitbox
	sprite.visible = false
	collision_shape.set_deferred("disabled", true)
	monitoring = false
	monitorable = false
	telegraph_line.visible = true


func _process(delta: float) -> void:
	if not is_striking:
		telegraph_timer -= delta
		# Flash the telegraph line
		var alpha: float = 0.2 + 0.6 * abs(sin(telegraph_timer * 12.0))
		telegraph_line.default_color = Color(1.0, 0.9, 0.3, alpha)
		if telegraph_timer <= 0:
			_start_strike()
	else:
		frame_timer += delta
		if frame_timer >= 1.0 / STRIKE_FPS:
			frame_timer -= 1.0 / STRIKE_FPS
			current_frame += 1
			if current_frame >= TOTAL_FRAMES:
				queue_free()
				return
			sprite.texture = textures[current_frame]
			# Disable hitbox after first few frames (active frames 0-5)
			if current_frame > 5 and not collision_shape.disabled:
				collision_shape.set_deferred("disabled", true)
				monitoring = false
				monitorable = false


func _start_strike() -> void:
	is_striking = true
	telegraph_line.visible = false
	sprite.visible = true
	sprite.texture = textures[0]
	# Enable damage hitbox
	collision_shape.set_deferred("disabled", false)
	monitoring = true
	monitorable = true
	# Screen shake for the lightning
	GameManager.apply_screen_shake(3.0, 0.1)
