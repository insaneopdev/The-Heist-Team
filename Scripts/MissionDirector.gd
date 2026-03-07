extends Node
class_name MissionDirector

# --- SIGNALS ---
signal phase_changed(new_phase)
signal assault_state_changed(is_assault)
signal drama_updated(drama_level)

# --- ENUMS ---
enum Phase { SETUP, ALERTED, DRILLING, LOOTING }

# --- EXPORTS: TIMINGS ---
@export_group("Timings")
@export var assault_duration := 60.0
@export var fade_duration := 45.0
@export var emergency_fade_duration := 30.0
@export var spawn_block_duration := 15.0
@export var assault_spawn_interval := 10.0
@export var fade_spawn_interval := 40.0

# --- EXPORTS: BALANCING ---
@export_group("Balancing")
@export var safe_spawn_distance := 18.0
@export var drama_threshold_to_fade := 0.75
@export var max_enemies_solo := 4
@export var max_enemies_mid := 10
@export var max_enemies_full := 16

# --- STATE ---
var current_phase : Phase = Phase.SETUP
var is_assault_wave := true
var wave_phase_timer := 0.0
var group_drama_level := 0.0
var spawn_blocked_by_drama := false
var player_health_snapshots := {} # { id: last_known_health }

# --- REFERENCES ---
var players_cache := []
var enemy_spawn_points := []
var cop_scene : PackedScene

func _ready():
	wave_phase_timer = assault_duration

func update_director(delta: float):
	if current_phase == Phase.SETUP:
		return
		
	_calculate_drama(delta)
	_manage_waves(delta)

func _calculate_drama(_delta: float):
	var total_stress := 0.0
	if players_cache.is_empty(): return
	
	for p in players_cache:
		if not is_instance_valid(p): continue
		var pid = p.get_instance_id()
		
		# 1. Downed Status
		if p.state == p.PlayerState.DOWNED:
			total_stress += 0.6
		
		# 2. HP Thresholds
		var health_pct = float(p.current_health) / float(p.max_health)
		if health_pct < 0.25: total_stress += 0.4
		elif health_pct < 0.5: total_stress += 0.2
		
		# 3. Damage Spikes
		if player_health_snapshots.has(pid):
			var last_hp = player_health_snapshots[pid]
			if p.current_health < last_hp:
				var dmg = last_hp - p.current_health
				total_stress += (float(dmg) / 100.0) * 0.5 
		
		player_health_snapshots[pid] = p.current_health
			
	var target_drama = clamp(total_stress / players_cache.size(), 0.0, 1.0)
	group_drama_level = lerp(group_drama_level, target_drama, 0.1)
	drama_updated.emit(group_drama_level)
	
	if is_assault_wave and group_drama_level >= drama_threshold_to_fade:
		force_fade_phase()

func _manage_waves(delta: float):
	wave_phase_timer -= delta
	if wave_phase_timer <= 0:
		is_assault_wave = !is_assault_wave
		if is_assault_wave:
			wave_phase_timer = assault_duration
		else:
			wave_phase_timer = fade_duration
		assault_state_changed.emit(is_assault_wave)

func force_fade_phase():
	is_assault_wave = false
	wave_phase_timer = emergency_fade_duration
	spawn_blocked_by_drama = true
	assault_state_changed.emit(false)
	get_tree().create_timer(spawn_block_duration).timeout.connect(func(): spawn_blocked_by_drama = false)

func get_max_enemy_cap() -> int:
	if not is_assault_wave: return 2
	var count = players_cache.size()
	if count <= 2: return max_enemies_solo
	if count <= 5: return max_enemies_mid
	return max_enemies_full

func get_reinforcement_count() -> int:
	var count = players_cache.size()
	if count <= 2: return 1
	if count <= 5: return 2
	return 3

func get_initial_wave_count() -> int:
	# Start with half of current cap or at least 2
	return max(2, get_max_enemy_cap() / 2)

func get_spawn_interval() -> float:
	return assault_spawn_interval if is_assault_wave else fade_spawn_interval

func set_phase(new_phase: Phase):
	current_phase = new_phase
	phase_changed.emit(new_phase)
