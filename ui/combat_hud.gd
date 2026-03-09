extends CanvasLayer

## Combat HUD – boss health bar (top-center) and player health bar (bottom-left).
## Finds player and boss in groups automatically, updates every frame.

@onready var boss_bar: ProgressBar = $BossHealthBar
@onready var boss_name_label: Label = $BossNameLabel
@onready var player_bar: ProgressBar = $PlayerHealthBar
@onready var stamina_bar: ProgressBar = $PlayerStaminaBar
@onready var potion_label: Label = $PotionLabel
@onready var game_over_panel: ColorRect = $GameOverPanel
@onready var victory_panel: ColorRect = $VictoryPanel
@onready var pause_panel: ColorRect = $PausePanel

var player: CharacterBody2D = null
var boss: CharacterBody2D = null


func _ready() -> void:
	# UI must process even when the game is paused!
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Wait a frame so every node is in the tree
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	boss = get_tree().get_first_node_in_group("boss")

	# Style the bars for that Hollow Knight dark aesthetic
	# Boss bar: bright vivid red so it pops against dark backgrounds
	_style_bar(boss_bar, Color(1.0, 0.2, 0.15), Color(0.2, 0.1, 0.1))
	_style_bar(player_bar, Color(0.95, 0.82, 0.35), Color(0.15, 0.12, 0.12))
	# Stamina: grey tone
	_style_bar(stamina_bar, Color(0.6, 0.6, 0.6), Color(0.15, 0.15, 0.15))

	if boss:
		boss_bar.max_value = boss.MAX_HP
		boss_bar.value = boss.hp
	if player:
		player_bar.max_value = player.health
		player_bar.value = player.health

	# UI setup
	game_over_panel.hide()
	victory_panel.hide()
	pause_panel.hide()
	GameManager.player_died.connect(_on_player_died)
	GameManager.boss_died.connect(_on_boss_died)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# Ignore pause if game is over
		if game_over_panel.visible or victory_panel.visible:
			return
		
		var tree = get_tree()
		tree.paused = !tree.paused
		pause_panel.visible = tree.paused

func _process(_delta: float) -> void:
	# Update boss bar
	if is_instance_valid(boss):
		boss_bar.visible = true
		boss_name_label.visible = true
		# Smooth lerp toward actual HP for a satisfying drain effect
		boss_bar.value = lerpf(boss_bar.value, float(boss.hp), 0.15)
	else:
		boss_bar.visible = false
		boss_name_label.visible = false

	# Update player bar
	if is_instance_valid(player):
		player_bar.value = player.health
		stamina_bar.value = player.stamina
		potion_label.text = "Potions: %d/%d" % [player.potions, player.MAX_POTIONS]


## Apply a flat dark style to a ProgressBar — fill_color for the front, bg_color for the back.
func _style_bar(bar: ProgressBar, fill_color: Color, bg_color: Color) -> void:
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.corner_radius_top_left = 2
	fill.corner_radius_top_right = 2
	fill.corner_radius_bottom_left = 2
	fill.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("fill", fill)

	var bg := StyleBoxFlat.new()
	bg.bg_color = bg_color
	bg.corner_radius_top_left = 2
	bg.corner_radius_top_right = 2
	bg.corner_radius_bottom_left = 2
	bg.corner_radius_bottom_right = 2
	# Thin border to frame the bar
	bg.border_color = Color(0.35, 0.3, 0.3, 0.8)
	bg.border_width_top = 1
	bg.border_width_bottom = 1
	bg.border_width_left = 1
	bg.border_width_right = 1
	bar.add_theme_stylebox_override("background", bg)

func _on_player_died() -> void:
	game_over_panel.show()
	# Quick reset after a tiny delay so the player sees the "YOU DIED" screen briefly
	await get_tree().create_timer(1.0).timeout
	get_tree().reload_current_scene()

func _on_boss_died() -> void:
	victory_panel.show()
