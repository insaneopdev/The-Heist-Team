extends Node
class_name MissionDirector

# --- SIGNALS ---
signal phase_changed(new_phase)
signal drama_updated(drama_level)
signal wave_completed(phase, wave_index)

# --- ENUMS ---
enum Phase { SETUP, ENTRY, DRILLING, LOOTING, ESCAPE }

# ==============================
# CONFIGURATION DICTIONARIES
# ==============================

# Phase specific rules: randomized waves and intervals
var phase_config = {
	Phase.ENTRY: {
		"min_waves": 1,
		"max_waves": 2,
		"min_interval": 8.0,
		"max_interval": 13.0,
		"base_limit": 4, # Per player scaling base
		"per_player": 2
	},
	Phase.DRILLING: {
		"min_waves": 2,
		"max_waves": 4,
		"min_interval": 10.0,
		"max_interval": 20.0,
		"base_limit": 5,
		"per_player": 3
	},
	Phase.LOOTING: {
		"min_waves": 1,
		"max_waves": 3,
		"min_interval": 10.0,
		"max_interval": 15.0,
		"base_limit": 3,
		"per_player": 2
	},
	Phase.ESCAPE: {
		"min_waves": 3,
		"max_waves": 5,
		"min_interval": 10.0,
		"max_interval": 15.0,
		"base_limit": 6,
		"per_player": 4
	}
}

# --- EXPORTS ---
@export_group("Balancing")
@export var safe_spawn_distance := 18.0
@export var drama_threshold_to_fade := 0.85
@export var adaptive_speed_up_timer := 5.0 # Seconds to wait if clearing fast
@export var adaptive_slow_down_multiplier := 1.5 # How much to delay if struggling

# --- STATE ---
var current_phase : Phase = Phase.SETUP
var group_drama_level := 0.0
var spawn_blocked_by_drama := false
var current_wave_index := 0
var total_waves_for_phase := 0 
var is_assault_wave := true

var player_health_snapshots := {} 
var players_cache := []
var enemy_spawn_points := []
var cop_scene : PackedScene

# --- LOGIC ---

func _ready():
	pass

func update_director(delta: float):
	if current_phase == Phase.SETUP: return
	_calculate_drama(delta)

func _calculate_drama(_delta: float):
	var total_stress := 0.0
	if players_cache.is_empty(): return
	
	for p in players_cache:
		if not is_instance_valid(p): continue
		var pid = p.get_instance_id()
		
		if p.state == p.PlayerState.DOWNED: total_stress += 0.6
		
		var health_pct = float(p.current_health) / float(p.max_health)
		if health_pct < 0.25: total_stress += 0.4
		elif health_pct < 0.5: total_stress += 0.2
		
		if player_health_snapshots.has(pid):
			var last_hp = player_health_snapshots[pid]
			if p.current_health < last_hp:
				total_stress += (float(last_hp - p.current_health) / 100.0) * 0.5 
		
		player_health_snapshots[pid] = p.current_health
			
	var target_drama = clamp(total_stress / players_cache.size(), 0.0, 1.0)
	group_drama_level = lerp(group_drama_level, target_drama, 0.1)
	drama_updated.emit(group_drama_level)
	
	# Adaptive logic: If drama is too high, block spawns briefly
	if group_drama_level >= drama_threshold_to_fade:
		spawn_blocked_by_drama = true
	else:
		spawn_blocked_by_drama = false

func get_max_enemy_cap() -> int:
	if not phase_config.has(current_phase): return 4
	var config = phase_config[current_phase]
	
	# Linear Scaling: Base + (Extra Players * multiplier)
	var player_count = players_cache.size()
	var base = config.get("base_limit", 4)
	var extra = config.get("per_player", 2) * max(0, player_count - 1)
	
	return base + extra

func get_spawn_interval() -> float:
	if not phase_config.has(current_phase): return 10.0
	var config = phase_config[current_phase]
	
	# Random Interval within Phase Range
	var min_i = config.get("min_interval", 10.0)
	var max_i = config.get("max_interval", 15.0)
	var interval = randf_range(min_i, max_i)
	
	# Adaptive Delay: If group is really struggling, give them even more time
	if group_drama_level > 0.7:
		interval *= adaptive_slow_down_multiplier
		
	return interval


func set_phase(new_phase: Phase):
	if current_phase == new_phase: return
	current_phase = new_phase
	current_wave_index = 0
	
	# ⚡ RANDOMIZE TOTAL WAVES FOR THIS PHASE Instance
	if phase_config.has(current_phase):
		var config = phase_config[current_phase]
		total_waves_for_phase = randi_range(config["min_waves"], config["max_waves"])
	else:
		total_waves_for_phase = 0
		
	phase_changed.emit(new_phase)

func can_spawn_more_waves() -> bool:
	return current_wave_index < total_waves_for_phase

func increment_wave():
	current_wave_index += 1
	wave_completed.emit(current_phase, current_wave_index)

func get_wave_progress_string() -> String:
	return str(current_wave_index) + "/" + str(total_waves_for_phase)
