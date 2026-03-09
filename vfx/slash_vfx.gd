extends Node2D

## Self-destroying slash VFX. Always uses the minimal red variant.

@onready var sprite: Sprite2D = $Sprite2D

var frame_timer: float = 0.0
var current_frame: int = 0

const TOTAL_FRAMES: int = 13
const VFX_FPS: float = 26.0

# Single consistent red minimal slash
var slash_texture: Texture2D = preload("res://asset/fx/slash/SlashFX 5A v1_1.png")


func _ready() -> void:
	sprite.texture = slash_texture
	sprite.frame = 0


func _process(delta: float) -> void:
	frame_timer += delta
	if frame_timer >= 1.0 / VFX_FPS:
		frame_timer -= 1.0 / VFX_FPS
		current_frame += 1
		if current_frame >= TOTAL_FRAMES:
			queue_free()
			return
		sprite.frame = current_frame
