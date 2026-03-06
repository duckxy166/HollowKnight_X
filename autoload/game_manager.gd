extends Node

## Global game manager - handles hitstop, parry effects, and game state.

@warning_ignore("unused_signal")  # emitted from player.gd, not here
signal parry_occurred(player: CharacterBody2D, enemy_area: Area2D)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Freeze the game for [param duration] seconds (hitstop effect).
## Uses ignore_time_scale timer so it works even at time_scale 0.
func apply_hitstop(duration: float = 0.07) -> void:
	Engine.time_scale = 0.0
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0


## Push [param body] away from [param from_position].
func apply_recoil(body: CharacterBody2D, from_position: Vector2, strength: float = 200.0) -> void:
	var dir = sign(body.global_position.x - from_position.x)
	if dir == 0:
		dir = 1
	body.velocity.x = dir * strength
	body.velocity.y = -strength * 0.5
