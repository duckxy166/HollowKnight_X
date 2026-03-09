extends CharacterBody2D

## Boss AI with 4-phase system. Phases escalate attacks and speed as HP drops.

# ── State Machine ──
enum BossState { IDLE, CHASE, ATTACK1, ATTACK2, COMBO, DELAY_ATTACK, PROJECTILE, LIGHTNING, HURT, DEATH, PARRY_STANCE, AIR_COUNTER }

# ── Constants ──
const MAX_HP: int = 40
const GRAVITY: float = 900.0
const MAX_FALL_SPEED: float = 450.0
const CHASE_SPEED: float = 100.0
const ATTACK_RANGE: float = 60.0
const CHASE_RANGE: float = 300.0

# Phase thresholds (HP values)
const PHASE_2_THRESHOLD: int = 30  # 75%
const PHASE_3_THRESHOLD: int = 20  # 50%
const PHASE_4_THRESHOLD: int = 10  # 25%

# Idle cooldowns per phase
const IDLE_COOLDOWNS: Array[float] = [1.5, 1.0, 0.8, 0.2]
# Animation speed multipliers per phase
const SPEED_MULTIPLIERS: Array[float] = [1.0, 1.2, 1.2, 1.4]

# Attack hitbox offset from the boss (should match scene pivot)
const ATTACK_HITBOX_POS := Vector2(25, -2)

# Combo timing
const COMBO_HITS: int = 3
const COMBO_GAP: float = 0.1  # seconds between combo hits

# Delay attack extra pause
const DELAY_PAUSE: float = 0.5

# Lightning attack
const LIGHTNING_CHARGE_TIME: float = 1.0
const LIGHTNING_STRIKES_BASE: int = 2  # strikes in phase 3
const LIGHTNING_STRIKES_P4: int = 4    # strikes in phase 4

# Parry stance — boss blocks player's attack then counters
const PARRY_CHANCE_PER_HIT: float = 0.15   # +15% per hit taken
const PARRY_CHANCE_MAX: float = 0.6         # cap at 60%
const PARRY_DECAY_RATE: float = 0.3         # decays per second when not being hit

# Air counter
const AIR_COUNTER_THRESHOLD: int = 3
const AIR_COUNTER_JUMP_SPEED: float = -400.0

# ── Runtime State ──
var hp: int = MAX_HP
var current_phase: int = 1
var state: BossState = BossState.IDLE
var dir: int = -1  # -1 = facing left (toward player by default)
var idle_timer: float = 0.0
var parry_chance: float = 0.0
var parry_did_block: bool = false   # true if boss blocked a hit during this stance
var player_air_count: int = 0
var attack_timer: float = 0.0
var hurt_timer: float = 0.0
var combo_count: int = 0
var delay_phase: int = 0  # 0=windup, 1=pause, 2=swing
var delay_timer: float = 0.0
var hitbox_active: bool = false
var is_dead: bool = false
var lightning_timer: float = 0.0
var lightning_spawned: bool = false

var player: CharacterBody2D = null
var projectile_scene: PackedScene = preload("res://boss_projectile.tscn")
var lightning_scene: PackedScene = preload("res://vfx/lightning_strike.tscn")

# ── Node References ──
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_hitbox: Area2D = $AttackPivot/AttackHitbox
@onready var attack_pivot: Node2D = $AttackPivot
@onready var hurtbox: Area2D = $Hurtbox
@onready var body_collision: CollisionShape2D = $CollisionShape2D
@onready var telegraph_sfx: AudioStreamPlayer = $TelegraphSFX
@onready var hurt_sfx: AudioStreamPlayer = $HurtSFX


func _ready() -> void:
	floor_constant_speed = true
	add_to_group("boss")
	# Boss attack hitbox starts fully hidden so player can't parry when boss isn't swinging
	attack_hitbox.monitoring = false
	attack_hitbox.monitorable = false

	# Find player in the scene
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	if player == null:
		# Fallback: find by node name
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player = players[0]
		else:
			# Try to find CharacterBody2D named Player
			player = get_parent().get_node_or_null("Player")

	# Listen for parry events
	GameManager.parry_occurred.connect(_on_parry_occurred)

	# Connect animation signals
	anim.animation_finished.connect(_on_animation_finished)

	_update_direction(-1)
	_enter_state(BossState.IDLE)


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# Parry chance decays over time so boss won't block forever
	if parry_chance > 0:
		parry_chance = maxf(parry_chance - PARRY_DECAY_RATE * delta, 0.0)

	# Track if player is in the air — boss uses this to decide air_counter
	if player and not player.is_on_floor():
		player_air_count += 1
	elif player and player.is_on_floor():
		player_air_count = max(player_air_count - 1, 0)

	# Gravity
	if not is_on_floor():
		velocity.y = min(velocity.y + GRAVITY * delta, MAX_FALL_SPEED)

	match state:
		BossState.IDLE:
			_process_idle(delta)
		BossState.CHASE:
			_process_chase(delta)
		BossState.ATTACK1, BossState.ATTACK2:
			_process_attack(delta)
		BossState.COMBO:
			_process_combo(delta)
		BossState.DELAY_ATTACK:
			_process_delay_attack(delta)
		BossState.PROJECTILE:
			_process_projectile(delta)
		BossState.LIGHTNING:
			_process_lightning(delta)
		BossState.HURT:
			_process_hurt(delta)
		BossState.PARRY_STANCE:
			_process_parry_stance(delta)
		BossState.AIR_COUNTER:
			_process_air_counter(delta)
		BossState.DEATH:
			velocity.x = 0.0

	move_and_slide()


# ── State Transitions ──

func _enter_state(new_state: BossState) -> void:
	state = new_state
	match new_state:
		BossState.IDLE:
			idle_timer = IDLE_COOLDOWNS[current_phase - 1]
			velocity.x = 0.0
			anim.speed_scale = 1.0
			anim.play("idle")
			attack_hitbox.monitoring = false
			attack_hitbox.monitorable = false
			hitbox_active = false

		BossState.CHASE:
			anim.speed_scale = SPEED_MULTIPLIERS[current_phase - 1]
			anim.play("run")

		BossState.ATTACK1:
			_face_player()
			_telegraph_attack()
			velocity.x = 0.0
			anim.speed_scale = SPEED_MULTIPLIERS[current_phase - 1]
			anim.play("attack1")
			attack_timer = 0.0
			hitbox_active = false
			# Hitbox activates on frame 3 via _process_attack

		BossState.ATTACK2:
			_face_player()
			_telegraph_attack()
			velocity.x = 0.0
			anim.speed_scale = SPEED_MULTIPLIERS[current_phase - 1]
			anim.play("attack2")
			attack_timer = 0.0
			hitbox_active = false

		BossState.COMBO:
			_face_player()
			_telegraph_attack()
			velocity.x = 0.0
			combo_count = 0
			anim.speed_scale = SPEED_MULTIPLIERS[current_phase - 1] * 1.3
			anim.play("attack3")
			attack_timer = 0.0
			hitbox_active = false

		BossState.DELAY_ATTACK:
			_face_player()
			_telegraph_attack()
			velocity.x = 0.0
			delay_phase = 0  # Start with wind-up
			delay_timer = 0.0
			anim.speed_scale = SPEED_MULTIPLIERS[current_phase - 1]
			anim.play("attack1")
			attack_timer = 0.0
			hitbox_active = false

		BossState.PROJECTILE:
			_face_player()
			_telegraph_attack()
			velocity.x = 0.0
			anim.speed_scale = SPEED_MULTIPLIERS[current_phase - 1]
			anim.play("attack3")
			attack_timer = 0.0
			hitbox_active = false

		BossState.LIGHTNING:
			_face_player()
			_telegraph_attack()
			velocity.x = 0.0
			anim.speed_scale = SPEED_MULTIPLIERS[current_phase - 1]
			anim.play("lighningCharge")
			lightning_timer = LIGHTNING_CHARGE_TIME
			lightning_spawned = false
			attack_hitbox.monitoring = false
			attack_hitbox.monitorable = false
			hitbox_active = false

		BossState.HURT:
			velocity.x = 0.0
			hurt_timer = 0.3
			anim.speed_scale = 1.0
			anim.play("takehit")
			attack_hitbox.monitoring = false
			attack_hitbox.monitorable = false
			hitbox_active = false

		BossState.DEATH:
			is_dead = true
			velocity = Vector2.ZERO
			anim.speed_scale = 1.0
			anim.play("death")
			attack_hitbox.monitoring = false
			attack_hitbox.monitorable = false
			hitbox_active = false
			hurtbox.monitoring = false
			hurtbox.monitorable = false
			body_collision.set_deferred("disabled", true)

		BossState.PARRY_STANCE:
			_face_player()
			velocity.x = 0.0
			parry_did_block = false
			attack_timer = 0.0
			# Play attack2 but pause at frame 1 as "guard" pose
			anim.speed_scale = 1.0
			anim.play("attack2")
			anim.set_frame_and_progress(1, 0.0)
			anim.pause()
			# Blue tint = guard mode (visual telegraph for the player)
			anim.modulate = Color(0.6, 0.7, 1.0, 1.0)
			# Hitbox active immediately — if player swings into this, it triggers parry
			attack_hitbox.monitoring = true
			attack_hitbox.monitorable = true
			hitbox_active = true

		BossState.AIR_COUNTER:
			_face_player()
			velocity.x = 0.0
			# Boss jumps upward toward player
			velocity.y = AIR_COUNTER_JUMP_SPEED
			anim.speed_scale = SPEED_MULTIPLIERS[current_phase - 1] * 1.2
			anim.play("attack1")  # overhead slash
			attack_timer = 0.0
			hitbox_active = false
			player_air_count = 0  # reset after using this move


# ── State Processing ──

func _process_idle(delta: float) -> void:
	velocity.x = 0.0
	idle_timer -= delta
	if idle_timer <= 0:
		if player and _distance_to_player() > ATTACK_RANGE:
			_enter_state(BossState.CHASE)
		else:
			_pick_and_enter_attack()


func _process_chase(delta: float) -> void:
	if player == null:
		_enter_state(BossState.IDLE)
		return

	_face_player()
	velocity.x = dir * CHASE_SPEED * SPEED_MULTIPLIERS[current_phase - 1]

	if _distance_to_player() <= ATTACK_RANGE:
		velocity.x = 0.0
		_pick_and_enter_attack()


func _process_attack(delta: float) -> void:
	attack_timer += delta
	velocity.x = move_toward(velocity.x, 0.0, 300.0 * delta)

	# Hitbox timing depends on attack type
	var frame_dur: float = 1.0 / (5.0 * SPEED_MULTIPLIERS[current_phase - 1])
	var hitbox_start: float = frame_dur * 4.0 # Default for Attack 1
	var hitbox_end: float = frame_dur * 5.5
	
	if state == BossState.ATTACK2:
		hitbox_start = frame_dur * 2.0
		hitbox_end = frame_dur * 4.0

	if not hitbox_active and attack_timer >= hitbox_start:
		attack_hitbox.monitoring = true
		attack_hitbox.monitorable = true
		hitbox_active = true

	if hitbox_active and attack_timer >= hitbox_end:
		attack_hitbox.monitoring = false
		attack_hitbox.monitorable = false
		hitbox_active = false

	# Lunge forward slightly when swinging
	if attack_timer >= hitbox_start and attack_timer < hitbox_start + frame_dur:
		velocity.x = dir * 80.0


func _process_combo(delta: float) -> void:
	attack_timer += delta
	velocity.x = move_toward(velocity.x, 0.0, 300.0 * delta)

	# attack3 has 8 frames — hitbox starts on frame 4
	var frame_dur: float = 1.0 / (5.0 * SPEED_MULTIPLIERS[current_phase - 1] * 1.3)
	var hitbox_start: float = frame_dur * 4.0
	var hitbox_end: float = frame_dur * 5.5

	if not hitbox_active and attack_timer >= hitbox_start:
		attack_hitbox.monitoring = true
		attack_hitbox.monitorable = true
		hitbox_active = true

	if hitbox_active and attack_timer >= hitbox_end:
		attack_hitbox.monitoring = false
		attack_hitbox.monitorable = false
		hitbox_active = false

	# Lunge on each hit
	if attack_timer >= hitbox_start and attack_timer < hitbox_start + frame_dur:
		velocity.x = dir * 60.0


func _process_delay_attack(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 300.0 * delta)

	match delay_phase:
		0:  # Wind-up phase: wait for frame 2, then pause
			attack_timer += delta
			var frame_dur: float = 1.0 / (5.0 * SPEED_MULTIPLIERS[current_phase - 1])
			if attack_timer >= frame_dur * 3.0:
				# Pause the animation at frame 2
				anim.pause()
				delay_phase = 1
				delay_timer = DELAY_PAUSE
		1:  # Pause phase: hold the wind-up pose
			delay_timer -= delta
			if delay_timer <= 0:
				# Resume with fast swing
				delay_phase = 2
				attack_timer = 0.0
				anim.speed_scale = SPEED_MULTIPLIERS[current_phase - 1] * 1.5
				anim.play("attack1")
				anim.set_frame_and_progress(3, 0.0)
		2:  # Swing phase
			attack_timer += delta
			var frame_dur: float = 1.0 / (5.0 * SPEED_MULTIPLIERS[current_phase - 1] * 1.5)

			if not hitbox_active and attack_timer >= frame_dur * 0.5:
				attack_hitbox.monitoring = true
				attack_hitbox.monitorable = true
				hitbox_active = true
				velocity.x = dir * 100.0

			if hitbox_active and attack_timer >= frame_dur * 2.5:
				attack_hitbox.monitoring = false
				attack_hitbox.monitorable = false
				hitbox_active = false


func _process_projectile(_delta: float) -> void:
	# Projectile spawns on animation_finished
	pass


func _process_lightning(delta: float) -> void:
	velocity.x = 0.0
	lightning_timer -= delta
	if not lightning_spawned and lightning_timer <= 0:
		lightning_spawned = true
		_spawn_lightning_strikes()
		# Wait for strikes to land before returning to idle
		lightning_timer = 0.8
	elif lightning_spawned and lightning_timer <= 0:
		_enter_state(BossState.IDLE)


func _process_hurt(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)
	hurt_timer -= delta
	if hurt_timer <= 0:
		_enter_state(BossState.IDLE)


# ── Animation Callback ──

func _on_animation_finished() -> void:
	if is_dead:
		return

	match state:
		BossState.ATTACK1, BossState.ATTACK2:
			attack_hitbox.monitoring = false
			attack_hitbox.monitorable = false
			hitbox_active = false
			_enter_state(BossState.IDLE)

		BossState.COMBO:
			attack_hitbox.monitoring = false
			attack_hitbox.monitorable = false
			hitbox_active = false
			combo_count += 1
			if combo_count < COMBO_HITS:
				# Next combo hit
				attack_timer = 0.0
				hitbox_active = false
				_face_player()
				anim.play("attack3")
			else:
				_enter_state(BossState.IDLE)

		BossState.DELAY_ATTACK:
			if delay_phase == 2:
				attack_hitbox.monitoring = false
				attack_hitbox.monitorable = false
				hitbox_active = false
				_enter_state(BossState.IDLE)

		BossState.PROJECTILE:
			_spawn_projectile()
			_enter_state(BossState.IDLE)

		BossState.DEATH:
			# Boss is dead, could emit signal or queue_free
			queue_free()

		BossState.HURT:
			pass  # Handled by timer


## Parry stance — boss holds guard pose with blue tint.
## If the player attacks into the active hitbox, parry_occurred fires and
## the boss counterattacks. If the window expires without a block, return to idle.
func _process_parry_stance(delta: float) -> void:
	attack_timer += delta
	velocity.x = 0.0

	if parry_did_block:
		# Boss blocked! Brief pause then counterattack
		if attack_timer >= 0.12:
			anim.modulate = Color.WHITE
			attack_hitbox.monitoring = false
			attack_hitbox.monitorable = false
			hitbox_active = false
			# Counterattack — fast attack1
			_enter_state(BossState.ATTACK1)
		return

	# Guard window lasts 0.5 seconds
	if attack_timer >= 0.5:
		# Nobody attacked — drop guard, go back to idle
		anim.modulate = Color.WHITE
		attack_hitbox.monitoring = false
		attack_hitbox.monitorable = false
		hitbox_active = false
		_enter_state(BossState.IDLE)


## Air counter — boss jumps up with an overhead slash to catch airborne players.
func _process_air_counter(delta: float) -> void:
	attack_timer += delta
	var frame_dur: float = 1.0 / (5.0 * SPEED_MULTIPLIERS[current_phase - 1] * 1.2)

	# Hitbox active from frame 2 to frame 5
	if not hitbox_active and attack_timer >= frame_dur * 2.0:
		attack_hitbox.monitoring = true
		attack_hitbox.monitorable = true
		hitbox_active = true

	if hitbox_active and attack_timer >= frame_dur * 5.0:
		attack_hitbox.monitoring = false
		attack_hitbox.monitorable = false
		hitbox_active = false

	# Once boss lands back on floor, go back to idle
	if attack_timer > frame_dur * 3.0 and is_on_floor():
		attack_hitbox.monitoring = false
		attack_hitbox.monitorable = false
		hitbox_active = false
		_enter_state(BossState.IDLE)


# ── Attack Selection ──

func _pick_and_enter_attack() -> void:
	_face_player()
	var attacks: Array[BossState] = []

	# Phase 1: attack1 and attack2
	attacks.append(BossState.ATTACK1)
	attacks.append(BossState.ATTACK2)

	# Phase 2+: add combo
	if current_phase >= 2:
		attacks.append(BossState.COMBO)

	# Phase 3+: add delay attack, projectile, and lightning
	if current_phase >= 3:
		attacks.append(BossState.DELAY_ATTACK)
		attacks.append(BossState.PROJECTILE)
		attacks.append(BossState.LIGHTNING)

	var chosen: BossState = attacks[randi() % attacks.size()]

	# If player has been jumping a lot, consider air counter
	if player and not player.is_on_floor() and player_air_count >= AIR_COUNTER_THRESHOLD:
		chosen = BossState.AIR_COUNTER

	_enter_state(chosen)


# ── Combat ──

func take_damage(amount: int, _from_position: Vector2) -> void:
	if is_dead:
		return

	# Check if boss auto-parries this hit (escalating chance)
	if parry_chance > 0 and randf() < parry_chance:
		_auto_parry()
		return

	hp -= amount
	hp = max(hp, 0)
	hurt_sfx.play()

	# Getting hit a lot makes boss more likely to parry next time
	parry_chance = min(parry_chance + PARRY_CHANCE_PER_HIT, PARRY_CHANCE_MAX)

	_update_phase()
	_brief_flash()  # quick visual flash, no stagger

	if hp <= 0:
		_enter_state(BossState.DEATH)


func _on_parry_occurred(_player_node: CharacterBody2D, enemy_area: Area2D) -> void:
	# Check if the parried area belongs to us
	if enemy_area != attack_hitbox:
		return
	if is_dead or state == BossState.DEATH:
		return

	if state == BossState.PARRY_STANCE:
		# Boss SUCCESSFULLY blocked the player's attack!
		# Don't stagger — mark the block and let _process_parry_stance counterattack
		parry_did_block = true
		attack_timer = 0.0  # reset timer for the counter delay
		# Flash white to show the clash
		anim.modulate = Color(3.0, 3.0, 3.0, 1.0)
		var tween := create_tween()
		tween.tween_property(anim, "modulate", Color(0.6, 0.7, 1.0, 1.0), 0.08)
	else:
		# Normal parry — boss staggers
		attack_hitbox.monitoring = false
		attack_hitbox.monitorable = false
		hitbox_active = false
		_brief_flash()
		hurt_timer = 0.2
		anim.speed_scale = 1.0
		anim.play("takehit")
		state = BossState.HURT


## Quick white flash when hit — boss keeps doing whatever it was doing.
func _brief_flash() -> void:
	var tween = create_tween()
	tween.tween_property(anim, "modulate", Color(3.0, 3.0, 3.0, 1.0), 0.03)
	tween.tween_property(anim, "modulate", Color.WHITE, 0.06)


## Boss auto-parries: enter a proper parry stance instead of just flashing.
func _auto_parry() -> void:
	if state == BossState.PARRY_STANCE or state == BossState.DEATH:
		return
	telegraph_sfx.play()
	_enter_state(BossState.PARRY_STANCE)


func _update_phase() -> void:
	var old_phase: int = current_phase
	if hp <= PHASE_4_THRESHOLD:
		current_phase = 4
	elif hp <= PHASE_3_THRESHOLD:
		current_phase = 3
	elif hp <= PHASE_2_THRESHOLD:
		current_phase = 2
	else:
		current_phase = 1

	if current_phase != old_phase:
		# Phase transition - could add visual feedback here
		anim.speed_scale = SPEED_MULTIPLIERS[current_phase - 1]


# ── Projectile ──

func _spawn_projectile() -> void:
	if player == null:
		return
	var proj = projectile_scene.instantiate()
	proj.global_position = global_position + Vector2(dir * 20, -5)
	var aim_dir := Vector2(dir, 0).normalized()
	proj.direction = aim_dir
	proj.boss_phase = current_phase
	get_parent().add_child(proj)


func _spawn_lightning_strikes() -> void:
	if player == null:
		return

	var strike_count: int = LIGHTNING_STRIKES_P4 if current_phase >= 4 else LIGHTNING_STRIKES_BASE
	# Get arena bounds from walls (roughly x=0 to x=1280)
	var arena_min_x: float = 20.0
	var arena_max_x: float = 1260.0
	# Floor y position (lightning spawns on the floor)
	var floor_y: float = global_position.y

	# One strike always targets player position
	var positions: Array[float] = [player.global_position.x]

	# Remaining strikes at spread positions around the arena
	for i in range(strike_count - 1):
		var rand_x := randf_range(arena_min_x, arena_max_x)
		positions.append(rand_x)

	for x_pos in positions:
		var strike = lightning_scene.instantiate()
		strike.global_position = Vector2(x_pos, floor_y)
		get_parent().add_child(strike)


# ── Helpers ──

## White flash + swipe sound before each attack — gives the player a split-second warning.
func _telegraph_attack() -> void:
	telegraph_sfx.play()
	# Quick bright-white flash on the boss sprite
	anim.modulate = Color(3.0, 3.0, 3.0, 1.0)  # overbright white glint
	var tween := create_tween()
	tween.tween_property(anim, "modulate", Color.WHITE, 0.1)

func _face_player() -> void:
	if player == null:
		return
	var new_dir: int = 1 if player.global_position.x > global_position.x else -1
	_update_direction(new_dir)


func _update_direction(new_dir: int) -> void:
	if new_dir == 0:
		return
	dir = new_dir
	anim.flip_h = (dir == -1)
	attack_pivot.scale.x = dir


func _distance_to_player() -> float:
	if player == null:
		return 9999.0
	return abs(player.global_position.x - global_position.x)
