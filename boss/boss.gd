extends CharacterBody2D

## Boss AI with 4-phase system. Phases escalate attacks and speed as HP drops.

enum BossState { IDLE, CHASE, ATTACK1, ATTACK2, COMBO, DELAY_ATTACK, PROJECTILE, LIGHTNING, HURT, DEATH, PARRY_STANCE, AIR_COUNTER, BACKSTEP }

# ── Constants ──
const MAX_HP: int = 40
const GRAVITY: float = 900.0
const MAX_FALL_SPEED: float = 450.0
const CHASE_SPEED: float = 160.0
const ATTACK_RANGE: float = 60.0
const CHASE_RANGE: float = 300.0

# Phase thresholds (HP values)
const PHASE_2_THRESHOLD: int = 30  # 75%
const PHASE_3_THRESHOLD: int = 20  # 50%
const PHASE_4_THRESHOLD: int = 10  # 25%

# Idle cooldowns per phase (shorter = more aggressive)
const IDLE_COOLDOWNS: Array[float] = [0.6, 0.4, 0.2, 0.0]
# Animation speed multipliers per phase
const SPEED_MULTIPLIERS: Array[float] = [1.0, 1.15, 1.3, 1.6]

# Attack hitbox offset from the boss (should match scene pivot)
const ATTACK_HITBOX_POS := Vector2(25, -2)

# Combo timing
const COMBO_HITS: int = 3
const COMBO_GAP: float = 0.1  # seconds between combo hits

# Delay attack extra pause
const DELAY_PAUSE: float = 0.5

# Lightning attack
const LIGHTNING_CHARGE_TIME: float = 1.0
const LIGHTNING_STRIKES_BASE: int = 3  # strikes in phase 3
const LIGHTNING_STRIKES_P4: int = 8    # strikes in phase 4

# Parry stance — boss blocks player's attack then counters
const PARRY_CHANCE_PER_HIT: float = 0.15   # +15% per hit taken
const PARRY_CHANCE_MAX: float = 0.6         # cap at 60%
const PARRY_DECAY_RATE: float = 0.3         # decays per second when not being hit

# Air counter
const AIR_COUNTER_THRESHOLD: int = 3
const AIR_COUNTER_JUMP_SPEED: float = -250.0

# ── Runtime State ──
var hp: int = MAX_HP
var current_phase: int = 1
var state: BossState = BossState.IDLE
var dir: int = -1  # -1 = facing left (toward player by default)
var idle_timer: float = 0.0
var parry_chance: float = 0.0
var parry_did_block: bool = false   # true if boss blocked a hit during this stance
var player_air_time: float = 0.0
var attack_timer: float = 0.0
var hurt_timer: float = 0.0
var combo_count: int = 0
var delay_phase: int = 0  # 0=windup, 1=pause, 2=swing
var delay_timer: float = 0.0
var hitbox_active: bool = false
var current_hit_parried: bool = false  # prevents hitbox from re-opening after a parry mid-swing
var is_dead: bool = false
var lightning_timer: float = 0.0
var lightning_spawned: bool = false

var player: CharacterBody2D = null
var projectile_scene: PackedScene = preload("res://boss/boss_projectile.tscn")
var lightning_scene: PackedScene = preload("res://vfx/lightning_strike.tscn")

# ── Node References ──
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_hitbox: Area2D = $AttackPivot/AttackHitbox
@onready var attack_pivot: Node2D = $AttackPivot
@onready var hurtbox: Area2D = $Hurtbox
@onready var body_collision: CollisionShape2D = $CollisionShape2D
@onready var telegraph_sfx: AudioStreamPlayer = $TelegraphSFX
@onready var hurt_sfx: AudioStreamPlayer = $HurtSFX
@onready var parry_sfx: AudioStreamPlayer = $ParrySFX
@onready var slash_sfx: AudioStreamPlayer = $SlashSFX
@onready var voice_player: AudioStreamPlayer = $VoicePlayer
@onready var hurt_voice_player: AudioStreamPlayer = $HurtVoicePlayer

var voice_hurts: Array[AudioStream] = [
	preload("res://asset/sfx/boss_voice/Voicy_Valorant Sova Ah  2  .mp3"),
	preload("res://asset/sfx/boss_voice/Voicy_Valorant Sova Ah  3  .mp3"),
	preload("res://asset/sfx/boss_voice/Voicy_Valorant Sova Ah  5  .mp3")
]
var voice_good: AudioStream = preload("res://asset/sfx/boss_voice/Voicy_Valorant Sova Good  2  .mp3")
var voice_flight: AudioStream = preload("res://asset/sfx/boss_voice/Voicy_Valorant Sova Take flight .mp3")
var voice_defeat: AudioStream = preload("res://asset/sfx/boss_voice/Voicy_Valorant Sova You failed now sleep .mp3")
var voice_victory: AudioStream = preload("res://asset/sfx/boss_voice/Voicy_Valorant Sova You all are wonderfull .mp3")
var voice_lightning: AudioStream = preload("res://asset/sfx/boss_voice/Voicy_Valorant Sova Nowhere to run  .mp3")


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
	GameManager.player_died.connect(_on_player_died)

	# Connect animation signals
	anim.animation_finished.connect(_on_animation_finished)

	_update_direction(-1)
	_enter_state(BossState.IDLE)


func _exit_tree() -> void:
	# Safety net: If boss dies and is deleted during a hit stop, reset time scale
	Engine.time_scale = 1.0


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# Parry chance decays over time so boss won't block forever
	if parry_chance > 0:
		parry_chance = maxf(parry_chance - PARRY_DECAY_RATE * delta, 0.0)

	# Track if player is in the air — boss uses this to decide air_counter
	if player and not player.is_on_floor():
		player_air_time += delta
	else:
		player_air_time = 0.0

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
		BossState.BACKSTEP:
			_process_backstep(delta)
		BossState.DEATH:
			velocity.x = 0.0

	move_and_slide()


# ── State Transitions ──

func _enter_state(new_state: BossState) -> void:
	state = new_state
	# Always reset per-swing flags so nothing leaks across states
	hitbox_active = false
	current_hit_parried = false
	# Reset hitbox position to default (air counter moves it above head)
	attack_hitbox.position = Vector2.ZERO
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
			# Clamp speed so attacks stay reactable even in phase 4
			anim.speed_scale = minf(SPEED_MULTIPLIERS[current_phase - 1] * 1.5, 2.0)
			anim.play("attack1")
			attack_timer = 0.0
			hitbox_active = false

		BossState.ATTACK2:
			_face_player()
			_telegraph_attack()
			velocity.x = 0.0
			anim.speed_scale = minf(SPEED_MULTIPLIERS[current_phase - 1] * 1.5, 2.0)
			anim.play("attack2")
			attack_timer = 0.0
			hitbox_active = false

		BossState.COMBO:
			_face_player()
			_telegraph_attack()
			# Extra charge-up flash to warn player: "a flurry is coming!"
			telegraph_sfx.pitch_scale = 1.3  # higher pitch = distinct warning
			velocity.x = 0.0
			combo_count = 0
			# Hit 1 starts at normal speed — the rhythm will change between hits
			anim.speed_scale = minf(SPEED_MULTIPLIERS[current_phase - 1] * 1.8, 2.0)
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
			# Voice line plays at START of charge so it works as a telegraph/warning
			voice_player.stream = voice_lightning
			voice_player.play()

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
			velocity.y = AIR_COUNTER_JUMP_SPEED
			anim.speed_scale = minf(SPEED_MULTIPLIERS[current_phase - 1] * 1.2, 2.0)
			anim.play("attack1")  # overhead slash
			attack_timer = 0.0
			hitbox_active = false
			player_air_time = 0.0
			# Move hitbox above boss's head to actually hit players standing on top
			attack_hitbox.position = Vector2(0, -40)
			
			voice_player.stream = voice_flight
			voice_player.play()

		BossState.BACKSTEP:
			_face_player()
			# Jump backward quickly
			velocity.x = -dir * CHASE_SPEED * 3.0
			velocity.y = -250.0
			anim.speed_scale = SPEED_MULTIPLIERS[current_phase - 1]
			anim.play("idle")  # use idle or whatever fits best as a retreat
			attack_timer = 0.0
			hitbox_active = false
			# i-frames while airborne so backstep actually works as an escape
			hurtbox.monitoring = false
			hurtbox.monitorable = false
			
			# Shake player off if they are riding the head
			if player and player.is_on_floor() and global_position.y - player.global_position.y > 30.0:
				if abs(global_position.x - player.global_position.x) < 30.0:
					# Push them forward (opposite of our backstep) and slightly up
					player.velocity.x = dir * 300.0
					player.velocity.y = -150.0


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
	var frame_dur: float = 1.0 / (5.0 * SPEED_MULTIPLIERS[current_phase - 1] * 1.5)
	# attack1: windup 3, hit 4
	var hitbox_start: float = frame_dur * 3.0 
	var hitbox_end: float = frame_dur * 4.5
	
	if state == BossState.ATTACK2:
		# attack2: windup 1, hit 2
		hitbox_start = frame_dur * 1.0
		hitbox_end = frame_dur * 3.0

	if not hitbox_active and attack_timer >= hitbox_start:
		_turn_on_hitbox(true)

	if hitbox_active and attack_timer >= hitbox_end:
		attack_hitbox.set_deferred("monitoring", false)
		attack_hitbox.set_deferred("monitorable", false)
		hitbox_active = false

	# Lunge forward slightly when swinging
	if attack_timer >= hitbox_start and attack_timer < hitbox_start + frame_dur:
		velocity.x = dir * 80.0


func _process_combo(delta: float) -> void:
	attack_timer += delta
	velocity.x = move_toward(velocity.x, 0.0, 300.0 * delta)

	# Use current anim speed_scale for frame timing
	var current_speed: float = anim.speed_scale
	# attack3 is an 8-frame animation at 5.0 FPS base
	var frame_dur: float = 1.0 / (5.0 * current_speed)
	# Opens just as the sword starts swinging down (around frame 3-4)
	var hitbox_start: float = frame_dur * 3.5

	# Open hitbox only if this swing hasn't been parried already
	if not hitbox_active and not current_hit_parried and attack_timer >= hitbox_start:
		slash_sfx.pitch_scale = randf_range(0.9, 1.1)
		_turn_on_hitbox(true)

	# Note: We NO LONGER close the hitbox via `attack_timer >= hitbox_end`.
	# During ultra-fast combos (3.0x speed), delta skips frames and causes the hitbox
	# to open and close in the exact same physics tick, making it deal 0 damage.
	# The hitbox will now remain open until `_on_animation_finished` cleans it up.

	# Lunge — short step for fast hits, big lunge for heavy finisher
	if attack_timer >= hitbox_start and attack_timer < hitbox_start + (frame_dur * 2.0):
		if combo_count == 2:  # finisher: commit hard
			velocity.x = dir * 100.0
		else:  # fast hits: small step so boss doesn't overshoot
			velocity.x = dir * 40.0


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
			_face_player() # Track player even if they roll behind us
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

			if not hitbox_active and attack_timer >= frame_dur * 0.2:
				velocity.x = dir * 150.0
				slash_sfx.pitch_scale = 0.8
				_turn_on_hitbox(true)

			if hitbox_active and attack_timer >= frame_dur * 2.0:
				attack_hitbox.set_deferred("monitoring", false)
				attack_hitbox.set_deferred("monitorable", false)
				hitbox_active = false


func _process_projectile(delta: float) -> void:
	# Spawn projectile mid-animation (around frame 3-4) instead of waiting for anim to finish
	attack_timer += delta
	var frame_dur: float = 1.0 / (5.0 * SPEED_MULTIPLIERS[current_phase - 1])
	if not hitbox_active and attack_timer >= frame_dur * 3.0:
		hitbox_active = true  # reuse flag to track "already spawned"
		_spawn_projectile()
		slash_sfx.play()


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
		if anim.animation == "death":
			hurt_voice_player.stop()  # kill lingering hurt grunts so they don't overlap the victory line
			voice_player.stream = voice_victory
			voice_player.play()
			GameManager.boss_died.emit()
			# Hide the boss sprite but keep the node alive until voice finishes
			visible = false
			await voice_player.finished
			queue_free()
		return

	match state:
		BossState.ATTACK1, BossState.ATTACK2:
			attack_hitbox.set_deferred("monitoring", false)
			attack_hitbox.set_deferred("monitorable", false)
			hitbox_active = false
			_enter_state(BossState.IDLE)

		BossState.COMBO:
			attack_hitbox.set_deferred("monitoring", false)
			attack_hitbox.set_deferred("monitorable", false)
			hitbox_active = false
			combo_count += 1
			
			if combo_count < COMBO_HITS:
				attack_timer = 0.0
				current_hit_parried = false  # reset for the next swing
				_face_player()
				
				# === Rhythm pattern: fast-fast-SLOW (ปัง-ปัง...ปึ้ง!) ===
				if combo_count == 1:
					# Hit 2: blazing fast — catch players who panic-dodge
					anim.speed_scale = minf(SPEED_MULTIPLIERS[current_phase - 1] * 2.5, 4.0)
				elif combo_count == 2:
					# Hit 3 (finisher): delayed heavy swing — bait early parry
					anim.speed_scale = minf(SPEED_MULTIPLIERS[current_phase - 1] * 1.2, 1.8)
				
				# Force frame 0 for clean rhythm timing
				anim.play("attack3")
				anim.set_frame_and_progress(0, 0.0)
			else:
				# Combo over — backstep or idle to give player breathing room
				telegraph_sfx.pitch_scale = 1.0  # reset pitch for next time
				if randf() < 0.5:
					_enter_state(BossState.BACKSTEP)
				else:
					_enter_state(BossState.IDLE)

		BossState.DELAY_ATTACK:
			if delay_phase == 2:
				attack_hitbox.set_deferred("monitoring", false)
				attack_hitbox.set_deferred("monitorable", false)
				hitbox_active = false
				_enter_state(BossState.IDLE)

		BossState.PROJECTILE:
			# Projectile now spawns mid-animation via _process_projectile
			hitbox_active = false
			_enter_state(BossState.IDLE)

		BossState.HURT:
			pass  # Handled by timer


## Parry stance — boss holds guard pose. Hitbox active on frame 1.
## If the player attacks into the active hitbox, parry_occurred fires and
## the boss counterattacks. If the window expires without a block, return to idle.
func _process_parry_stance(delta: float) -> void:
	attack_timer += delta
	velocity.x = 0.0
	var frame_dur: float = 1.0 / (5.0 * SPEED_MULTIPLIERS[current_phase - 1])

	# Hitbox active on frame 1
	if not hitbox_active and attack_timer >= frame_dur * 1.0:
		_turn_on_hitbox(false)

	if parry_did_block:
		# Boss blocked! Brief pause then counterattack
		if attack_timer >= 0.12:
			anim.modulate = Color.WHITE
			attack_hitbox.set_deferred("monitoring", false)
			attack_hitbox.set_deferred("monitorable", false)
			hitbox_active = false
			# Counterattack — fast attack1
			_enter_state(BossState.ATTACK1)
		return

	# Guard window lasts 0.5 seconds
	if attack_timer >= 0.5:
		# Nobody attacked — drop guard, go back to idle
		anim.modulate = Color.WHITE
		attack_hitbox.set_deferred("monitoring", false)
		attack_hitbox.set_deferred("monitorable", false)
		hitbox_active = false
		_enter_state(BossState.IDLE)


## Air counter — boss launches upward with an overhead slash to punish airborne players.
func _process_air_counter(delta: float) -> void:
	attack_timer += delta
	var frame_dur: float = 1.0 / (5.0 * SPEED_MULTIPLIERS[current_phase - 1] * 1.2)

	# Keep thrusting upward during the windup/swing phase
	if attack_timer < frame_dur * 3.0:
		velocity.y = AIR_COUNTER_JUMP_SPEED

	# Hitbox active from the start — wide upward sweep
	if not hitbox_active and attack_timer >= 0.0:
		slash_sfx.pitch_scale = 1.2
		_turn_on_hitbox(true)

	# Shut hitbox after the swing arc
	if hitbox_active and attack_timer >= frame_dur * 5.0:
		attack_hitbox.set_deferred("monitoring", false)
		attack_hitbox.set_deferred("monitorable", false)
		hitbox_active = false

	# Landing logic: after swing phase, either slam down or land
	if attack_timer > frame_dur * 3.0:
		attack_hitbox.set_deferred("monitoring", false)
		attack_hitbox.set_deferred("monitorable", false)
		hitbox_active = false
		if is_on_floor():
			_enter_state(BossState.IDLE)
		else:
			# Gravity spike — slam back down fast instead of floating
			velocity.y += 1500.0 * delta


## Backstep — boss quickly jumps backward to reposition.
## Has i-frames while airborne so it actually works as an escape maneuver.
func _process_backstep(delta: float) -> void:
	attack_timer += delta
	if is_on_floor() and attack_timer > 0.1:
		hurtbox.set_deferred("monitoring", true)
		hurtbox.set_deferred("monitorable", true)
		velocity.x = move_toward(velocity.x, 0.0, 800.0 * delta)
		if is_zero_approx(velocity.x):
			# Chain into a counter-attack instead of going back to idle like an idiot
			if current_phase >= 2 and randf() < 0.6:
				_enter_state(BossState.PROJECTILE)  # backstep + shoot
			else:
				_enter_state(BossState.IDLE)


# ── Attack Selection ──

func _pick_and_enter_attack() -> void:
	_face_player()
	
	# Calculate distances with separate axes for accurate checks
	var dist = _distance_to_player()
	var y_dist: float = 0.0  # positive = player is above boss
	var x_dist: float = 999.0  # horizontal only
	
	if player:
		y_dist = global_position.y - player.global_position.y
		x_dist = abs(global_position.x - player.global_position.x)

	var chosen: BossState = BossState.IDLE

	# 1. Head-riding check FIRST (highest priority) — uses x_dist, not Euclidean dist
	if y_dist > 30.0 and x_dist < 30.0:
		if current_phase >= 3:
			_enter_state(BossState.LIGHTNING)  # self-targeted zap to punish the rider
		else:
			_enter_state(BossState.BACKSTEP)  # roll away to shake them off
		return

	# 2. Anti-air: player airborne too long or floating above but not directly on top
	if player and ((not player.is_on_floor() and player_air_time >= 0.3) or y_dist > 40.0):
		_enter_state(BossState.AIR_COUNTER)
		return

	# 3. Ground-based zone selection
	if dist <= ATTACK_RANGE * 1.5:
		# --- Melee zone ---
		var melee_pool = [BossState.ATTACK1, BossState.ATTACK2]
		if current_phase >= 2:
			melee_pool.append(BossState.COMBO)
		if current_phase >= 3:
			melee_pool.append(BossState.DELAY_ATTACK)
		
		if dist < ATTACK_RANGE * 0.8 and current_phase >= 2 and randf() < 0.4:
			chosen = BossState.BACKSTEP
		else:
			chosen = melee_pool.pick_random()

	elif dist <= ATTACK_RANGE * 4.0:
		# --- Mid range ---
		var mid_pool = [BossState.CHASE]
		if current_phase >= 2:
			mid_pool.append(BossState.PROJECTILE)
			mid_pool.append(BossState.DELAY_ATTACK)
		chosen = mid_pool.pick_random()

	else:
		# --- Long range ---
		var long_pool = [BossState.CHASE]
		if current_phase >= 2:
			long_pool.append(BossState.PROJECTILE)
		if current_phase >= 3:
			long_pool.append(BossState.LIGHTNING)
		chosen = long_pool.pick_random()

	_enter_state(chosen)


func _on_player_died() -> void:
	if not is_dead:
		voice_player.stream = voice_defeat
		voice_player.play()
		# Stop fighting — no more corpse-stomping after player is dead
		player = null
		_enter_state(BossState.IDLE)


# ── Combat ──

func take_damage(amount: int, _from_position: Vector2) -> void:
	if is_dead:
		return

	# Guard break FIRST — stagger only, no HP loss
	if state == BossState.PARRY_STANCE:
		_enter_state(BossState.HURT)
		return
	else:
		# Hyper armor: boss won't cancel committal attacks into a parry
		var hyper_armor_states = [BossState.LIGHTNING, BossState.PROJECTILE, BossState.AIR_COUNTER, BossState.DELAY_ATTACK]
		if state not in hyper_armor_states and parry_chance > 0 and randf() < parry_chance:
			_auto_parry()
			return

	hp -= amount
	hp = max(hp, 0)
	hurt_sfx.play()
	
	# Separate audio channel for hurt grunts — won't cut off speech lines
	if randf() < 0.8 and not hurt_voice_player.playing:
		hurt_voice_player.stream = voice_hurts.pick_random()
		hurt_voice_player.play()

	# Getting hit a lot makes boss more likely to parry next time
	parry_chance = min(parry_chance + PARRY_CHANCE_PER_HIT, PARRY_CHANCE_MAX)

	_update_phase()
	_brief_flash()  # quick visual flash, no stagger

	if hp <= 0:
		_enter_state(BossState.DEATH)


func _on_parry_occurred(_player_node: CharacterBody2D, enemy_area: Area2D) -> void:
	if enemy_area != attack_hitbox:
		return
	if is_dead or state == BossState.DEATH:
		return

	if state == BossState.PARRY_STANCE:
		# Boss SUCCESSFULLY blocked the player's attack!
		parry_did_block = true
		attack_timer = 0.0
		_apply_hit_stop(0.1, 0.01)  # dramatic freeze — boss shows dominance
		
		anim.modulate = Color(3.0, 3.0, 3.0, 1.0)
		var tween := create_tween()
		tween.tween_property(anim, "modulate", Color(0.6, 0.7, 1.0, 1.0), 0.08)
		parry_sfx.play()
	else:
		# Player parried the boss — kill the hitbox so it can't re-open
		attack_hitbox.set_deferred("monitoring", false)
		attack_hitbox.set_deferred("monitorable", false)
		hitbox_active = false
		current_hit_parried = true  # lock this swing's hitbox permanently
		
		if state == BossState.COMBO and combo_count < COMBO_HITS - 1:
			# Mid-combo parry: boss doesn't flinch! Flurry continues relentlessly
			_apply_hit_stop(0.02, 0.1)
			_brief_flash()  # visual feedback only — no stagger, no state change
			parry_sfx.play()
		else:
			# Finisher parry or normal attack parry: boss staggers!
			if state == BossState.COMBO:
				_apply_hit_stop(0.15, 0.02)  # big satisfying freeze
			else:
				_apply_hit_stop(0.08, 0.1)
			
			_brief_flash()
			hurt_timer = 0.2
			anim.speed_scale = 1.0
			anim.play("takehit")
			state = BossState.HURT
			
			# 15% chance boss acknowledges a good parry
			if randf() < 0.15:
				voice_player.stream = voice_good
				voice_player.play()


## Quick white flash when hit — boss keeps doing whatever it was doing.
func _brief_flash() -> void:
	var tween = create_tween()
	tween.tween_property(anim, "modulate", Color(3.0, 3.0, 3.0, 1.0), 0.03)
	tween.tween_property(anim, "modulate", Color.WHITE, 0.06)


## Boss auto-parries: enter parry stance AND force-stagger the player immediately.
## This avoids a physics desync where Godot's Area2D won't re-fire area_entered
## if the player's sword is already overlapping the boss hitbox in the same frame.
func _auto_parry() -> void:
	if state == BossState.PARRY_STANCE or state == BossState.DEATH:
		return
	telegraph_sfx.play()
	_enter_state(BossState.PARRY_STANCE)
	# Force-stagger the player so the parry can't be ignored by physics
	if player and player.has_method("on_parried_by_boss"):
		player.on_parried_by_boss()


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
	
	var spawn_pos = global_position + Vector2(dir * 20, -5)
	var aim_dir: Vector2 = (player.global_position - spawn_pos).normalized()
	
	# Phase 4 shoots a 3-way spread!
	var count: int = 3 if current_phase >= 4 else 1
	var spread: float = 0.25 # radians
	
	for i in range(count):
		var proj = projectile_scene.instantiate()
		proj.global_position = spawn_pos
		
		var final_dir = aim_dir
		if count > 1:
			var angle_offset = (i - 1) * spread
			final_dir = aim_dir.rotated(angle_offset)
			
		proj.direction = final_dir
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

	# Calculate lead distance predicting player's movement
	var lead_distance: float = 0.0
	if player.has_method("get_real_velocity"):
		lead_distance = player.get_real_velocity().x * 0.5
	elif "velocity" in player:
		lead_distance = player.velocity.x * 0.5
	
	var target_x: float
	
	# If player is head-riding, strike our own head to shake them off!
	if abs(global_position.x - player.global_position.x) < 30.0 and global_position.y - player.global_position.y > 30.0:
		target_x = global_position.x
	else:
		target_x = clamp(player.global_position.x + lead_distance, arena_min_x, arena_max_x)

	# One strike targets predicted player position
	var positions: Array[float] = [target_x]

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


## Bulletproof Hitbox Activation
## Forces a manual check for players already standing inside the hitbox
func _turn_on_hitbox(play_sound: bool = true) -> void:
	attack_hitbox.set_deferred("monitoring", true)
	attack_hitbox.set_deferred("monitorable", true)
	hitbox_active = true
	if play_sound:
		slash_sfx.play()

	# Overlap Desync Fix: defer so monitoring is on when the check runs
	call_deferred("_check_initial_overlaps")

func _check_initial_overlaps() -> void:
	if not hitbox_active:
		return
	var overlapping_areas = attack_hitbox.get_overlapping_areas()
	var parried_this_frame = false

	# 1. เช็คก่อนว่าดาบเรา ไปซ้อนทับกับดาบผู้เล่น (AttackHitbox) หรือไม่?
	for area in overlapping_areas:
		if area.name == "AttackHitbox" and area.get_parent().has_method("_handle_parry"):
			area.get_parent()._handle_parry(attack_hitbox)
			parried_this_frame = true
			break

	# 2. ถ้าไม่ได้โดนปัดป้อง ค่อยเช็คว่าฟันโดนตัว (Hurtbox) ไหม
	if not parried_this_frame:
		for area in overlapping_areas:
			if area.name == "Hurtbox" and area.get_parent().has_method("take_damage"):
				var p = area.get_parent()
				if p.has_method("is_auto_parrying") and p.is_auto_parrying():
					p._handle_parry(attack_hitbox)
				else:
					p.take_damage(1, global_position)

func _update_direction(new_dir: int) -> void:
	if new_dir == 0:
		return
	dir = new_dir
	anim.flip_h = (dir == -1)
	attack_pivot.scale.x = dir


## Freeze the game for a split-second on big clashes — makes hits feel weighty (Sekiro-style)
func _apply_hit_stop(duration: float = 0.08, time_scale: float = 0.05) -> void:
	Engine.time_scale = time_scale
	# Timer uses ignore_time_scale=true, so pass real-world duration directly (no multiplication!)
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0


func _distance_to_player() -> float:
	if player == null:
		return 9999.0
	return global_position.distance_to(player.global_position)
