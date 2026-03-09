extends Node
class_name MissionDirector

# --- SIGNALS ---
signal phase_changed(new_phase)
signal assault_state_changed(is_assault)
signal drama_updated(drama_level)
signal wave_completed(phase, wave_index)

# --- ENUMS ---
enum Phase { SETUP, ENTRY, DRILLING, LOOTING, ESCAPE }

# ==============================
# CONFIGURATION DICTIONARIES
# ==============================

# Phase specific rules: max waves, special thresholds, etc.
var phase_config = {
	Phase.ENTRY: {
		"max_waves": 1,
		"clear_threshold": 4, # Wave nearly cleared when count <= 4
		"initial_burst": true
	},
	Phase.DRILLING: {
		"max_waves": 2,
		"duration": 50.0,
		"interval": 20.0 # Standard interval between the 2 waves
	},
	Phase.LOOTING: {
		"max_waves": 1,
		"interval": 30.0
	},
	Phase.ESCAPE: {
		"max_waves": 3,
		"interval": 25.0
	}
}

# Enemy limits based on player count brackets
var bracket_config = {
	"small": {
		"range": range(1, 3), # 1-2 players
		"limits": {
			Phase.ENTRY: 4,
			Phase.DRILLING: 5,
			Phase.LOOTING: 3,
			Phase.ESCAPE: 6
		}
	},
	"medium": {
		"range": range(3, 6), # 3-5 players
		"limits": {
			Phase.ENTRY: 5,
			Phase.DRILLING: 8,
			Phase.LOOTING: 6,
			Phase.ESCAPE: 9
		}
	},
	"large": {
		"range": range(6, 9), # 6-8 players
		"limits": {
			Phase.ENTRY: 8,
			Phase.DRILLING: 10,
			Phase.LOOTING: 8,
			Phase.ESCAPE: 12
		}
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
	var bracket = _get_current_bracket()
	if not bracket or not phase_config.has(current_phase): 
		return 4 # Default fallback
	
	var limits = bracket["limits"]
	return limits.get(current_phase, 4)

func get_spawn_interval() -> float:
	if not phase_config.has(current_phase): return 10.0
	var base_interval = phase_config[current_phase].get("interval", 15.0)
	
	# Adaptive: If group is stressed, increase wait time
	if group_drama_level > 0.5:
		return base_interval * adaptive_slow_down_multiplier
	
	return base_interval

func _get_current_bracket() -> Dictionary:
	var count = players_cache.size()
	for key in bracket_config:
		if count in bracket_config[key]["range"]:
			return bracket_config[key]
	# Fallback for large groups or solo
	return bracket_config["small"] if count <= 2 else bracket_config["large"]

func set_phase(new_phase: Phase):
	if current_phase == new_phase: return
	current_phase = new_phase
	current_wave_index = 0
	phase_changed.emit(new_phase)

func can_spawn_more_waves() -> bool:
	if not phase_config.has(current_phase): return false
	return current_wave_index < phase_config[current_phase]["max_waves"]

func increment_wave():
	current_wave_index += 1
	wave_completed.emit(current_phase, current_wave_index)

func get_wave_progress_string() -> String:
	if not phase_config.has(current_phase): return ""
	var max_w = phase_config[current_phase]["max_waves"]
	return str(current_wave_index) + "/" + str(max_w)
