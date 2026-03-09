extends Area2D

## Lightning bolt from the sky. Telegraphs with a flashing line,
## then a vertical laser-like bolt strikes down from above.

const DAMAGE: int = 1
const TELEGRAPH_DURATION: float = 0.7
const STRIKE_FPS: float = 22.0
const TOTAL_FRAMES: int = 13

var textures: Array[Texture2D] = []
var current_frame: int = 0
var frame_timer: float = 0.0
var is_striking: bool = false
var telegraph_timer: float = TELEGRAPH_DURATION

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var telegraph_line: Line2D = $TelegraphLine
@onready var danger_line: Line2D = $DangerLine


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
	danger_line.visible = true
	danger_line.default_color = Color(1.0, 0.3, 0.1, 0.0)


func _process(delta: float) -> void:
	if not is_striking:
		_process_telegraph(delta)
	else:
		_process_strike(delta)


func _process_telegraph(delta: float) -> void:
	telegraph_timer -= delta
	var progress: float = 1.0 - (telegraph_timer / TELEGRAPH_DURATION)

	# Thin line flashes faster as it gets closer to striking
	var flash_speed: float = 8.0 + progress * 20.0
	var alpha: float = 0.2 + (0.6 * abs(sin(telegraph_timer * flash_speed)))
	telegraph_line.default_color = Color(1.0, 0.9, 0.3, alpha)
	telegraph_line.width = 1.0 + progress * 2.0

	# Danger zone fades in during the last 40% of telegraph
	if progress > 0.6:
		var danger_alpha: float = (progress - 0.6) / 0.4 * 0.15
		danger_line.default_color = Color(1.0, 0.3, 0.1, danger_alpha)

	if telegraph_timer <= 0:
		_start_strike()


func _start_strike() -> void:
	is_striking = true
	telegraph_line.visible = false
	danger_line.visible = false
	sprite.visible = true
	sprite.texture = textures[0]
	# Bright flash on the bolt itself
	sprite.modulate = Color(2.0, 2.0, 2.5, 1.0)
	# Enable damage hitbox
	collision_shape.set_deferred("disabled", false)
	monitoring = true
	monitorable = true
	# Impact effects
	GameManager.apply_screen_shake(4.0, 0.15)
	GameManager.apply_screen_flash(0.05)


func _process_strike(delta: float) -> void:
	frame_timer += delta

	# Fade the bolt brightness over time
	var life_progress: float = float(current_frame) / float(TOTAL_FRAMES)
	var brightness: float = lerpf(2.0, 0.8, life_progress)
	sprite.modulate = Color(brightness, brightness, brightness * 1.2, 1.0)

	if frame_timer >= 1.0 / STRIKE_FPS:
		frame_timer -= 1.0 / STRIKE_FPS
		current_frame += 1
		if current_frame >= TOTAL_FRAMES:
			queue_free()
			return
		sprite.texture = textures[current_frame]
		# Disable hitbox after first few active frames (0-4)
		if current_frame > 4 and not collision_shape.disabled:
			collision_shape.set_deferred("disabled", true)
			monitoring = false
			monitorable = false
