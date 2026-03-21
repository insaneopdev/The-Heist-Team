extends Node3D

# ==============================
# SCENES & COMPONENTS
# ==============================
@export var player_scene : PackedScene
@export var watchman_scene : PackedScene
@export var cop_scene : PackedScene

# --- NEW: CUSTOMIZABLE SPAWN SETTINGS ---
@export_group("Solo Spawn Settings")
@export var min_cops_per_trigger: int = 4
@export var max_cops_per_trigger: int = 7
@export var min_spawn_delay: float = 5.0
@export var max_spawn_delay: float = 10.0

# The new logic heart
var director : MissionDirector = MissionDirector.new()

# ==============================
# SCENE REFERENCES
# ==============================
@onready var spawn_points := $SpawnPoints.get_children()
@onready var setup_points := $setup.get_children()
@onready var enemy_spawn := $enemy_spawn.get_children()

@onready var anim = $NavigationRegion3D/bank/AnimationPlayer
@onready var drill = $NavigationRegion3D/bank/drill
@onready var particles = $NavigationRegion3D/bank/GPUParticles3D
@onready var timer = $NavigationRegion3D/bank/drilltime
@onready var label = $Area3D/Label3D

# ==============================
# LOCAL STATE & SPAWN LOGIC
# ==============================
var _players_spawned := false
@onready var cop_spawn_timer : Timer = Timer.new()
var _cops_left_in_sequence := 0
var _active_cops := 0 # NEW: Tracks cops currently alive in the scene
var current_drama_display := 0.0

# ==============================
# READY
# ==============================
func _ready():
	randomize()
	add_child(director)
	
	# Setup Director
	director.cop_scene = cop_scene
	director.enemy_spawn_points = enemy_spawn
	director.drama_updated.connect(_on_drama_updated)
	director.phase_changed.connect(_on_phase_changed)
	
	# Setup the single-cop Spawn Timer
	cop_spawn_timer.one_shot = true
	cop_spawn_timer.timeout.connect(_on_cop_spawn_timer_timeout)
	add_child(cop_spawn_timer)

	if multiplayer.is_server():
		_spawn_initial_watchmen()

	if not _players_spawned:
		_players_spawned = true
		_spawn_existing_players()

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	GameManager.enemy_died_signal.connect(_on_enemy_killed)
	
	_update_player_cache()
	
	# Initial sync for late joiners
	if multiplayer.is_server():
		_broadcast_mission_state()

	drill.visible = false
	particles.emitting = false

# ==============================
# PROCESS & UI JUICE
# ==============================
var _ui_timer := 0.0
var _target_label_color : Color = Color.WHITE
@onready var _original_label_pos : Vector3 = label.position

func _process(delta):
	_ui_timer += delta
	if multiplayer.is_server():
		if director.current_phase == director.Phase.SETUP:
			_check_setup_watchmen_dead()
		else:
			director.update_director(delta)

	_update_ui()
	_apply_ui_juice(delta)

func _apply_ui_juice(delta):
	label.modulate = label.modulate.lerp(_target_label_color, delta * 5.0)
	
	var pulse_speed = 4.0
	var pulse_amt = 0.05
	
	if director.current_phase == director.Phase.LOOTING:
		pulse_speed = 8.0
		pulse_amt = 0.12
	
	var s = 1.0 + sin(_ui_timer * pulse_speed) * pulse_amt
	label.scale = label.scale.lerp(Vector3.ONE * s, delta * 10.0)
	label.position.y = _original_label_pos.y + sin(_ui_timer * 1.5) * 0.1
	
	if director.group_drama_level > 0.6:
		label.rotation.z = sin(_ui_timer * 20.0) * 0.02

# ==============================
# UI TEXT UPDATES
# ==============================
func _on_drama_updated(_val):
	pass 

func _update_ui():
	var money_needed = GameManager.min_loot_required - GameManager.total_loot
	
	# COMBINED THREAT: Cops waiting to spawn + Cops currently alive
	var total_threats = _cops_left_in_sequence + _active_cops
	var wave_info = str(total_threats) + " Cops Remaining" if total_threats > 0 else "Area Clear"

	if money_needed > 0 and director.current_phase != director.Phase.SETUP:
		label.text = "NEED $" + str(money_needed) + " MORE\nThreat: " + wave_info
		_target_label_color = Color.RED
		return

	match director.current_phase:
		director.Phase.LOOTING:
			var money_status = "READY TO ESCAPE" if GameManager.total_loot >= GameManager.min_loot_required else "COLLECT $" + str(GameManager.min_loot_required - GameManager.total_loot)
			label.text = "VAULT OPEN: COLLECT LOOT\nLoot: " + money_status + "\nThreat: " + wave_info
			_target_label_color = Color.GOLD
		director.Phase.ESCAPE:
			# Van only opens if NO cops are waiting to spawn AND NO cops are alive
			if total_threats <= 0:
				label.text = "✨ GET IN THE VAN NOW! ✨\nVan is leaving!"
				_target_label_color = Color.GREEN
			else:
				label.text = "VAN IS PINNED DOWN!\n(Defend until van can move)\nThreat: " + wave_info
				_target_label_color = Color.ORANGE
		director.Phase.SETUP:
			label.text = "INFILTRATE THE BANK"
			_target_label_color = Color.WHITE
		_:
			var status = "HOLDING POSITION"
			if director.current_phase == director.Phase.DRILLING: 
				status = "DRILLING: " + str(int(timer.time_left)) + "s LEFT"
			
			var wave_text = "POLICE ASSAULT" if total_threats > 0 else "POLICE REGROUPING"
			current_drama_display = lerp(current_drama_display, director.group_drama_level, 0.05)
			var drama_pct = int(current_drama_display * 100)
			
			label.text = status + "\n" + wave_text + "\nStress: " + str(drama_pct) + "%"
			
			if drama_pct > 70: _target_label_color = Color(1.0, 0.4, 0.0)
			else: _target_label_color = Color.RED

# ==============================
# THE "SINGLE COP" SPAWN SYSTEM
# ==============================
func _start_trigger_sequence(trigger_name: String):
	if not multiplayer.is_server(): return
	
	print("LOGIC: Trigger activated: ", trigger_name)
	
	_cops_left_in_sequence += randi_range(min_cops_per_trigger, max_cops_per_trigger)
	
	if cop_spawn_timer.is_stopped():
		_schedule_next_cop()

func _schedule_next_cop():
	if _cops_left_in_sequence > 0:
		var delay = randf_range(min_spawn_delay, max_spawn_delay)
		cop_spawn_timer.start(delay)

func _on_cop_spawn_timer_timeout():
	if not multiplayer.is_server(): return
	
	# SPAWN EXACTLY ONE COP
	var marker = _get_furthest_or_safe_marker()
	if is_instance_valid(marker):
		var cop = cop_scene.instantiate()
		add_child(cop)
		cop.global_position = marker.global_position + _get_spawn_offset(1.5)
		cop.set_multiplayer_authority(multiplayer.get_unique_id())
		
		_active_cops += 1 # NEW: Track that a cop is now alive and in the scene
	
	_cops_left_in_sequence -= 1
	_schedule_next_cop()

# --- THE FIX: COUNTING COP DEATHS ---
func _on_enemy_killed():
	if multiplayer.is_server():
		if _active_cops > 0:
			_active_cops -= 1
			print("LOGIC: Cop killed. Active cops remaining: ", _active_cops)

# ==============================
# MISSION OBJECTIVES & TRIGGERS
# ==============================
func _enter_alerted_state():
	if director.current_phase != director.Phase.SETUP: return
	director.set_phase(director.Phase.ENTRY)
	_start_trigger_sequence("Initial Entry") # Trigger 1

func plant():
	if multiplayer.is_server() and director.current_phase == director.Phase.ENTRY:
		rpc("sync_start_drill")

@rpc("authority", "call_local")
func sync_start_drill():
	director.set_phase(director.Phase.DRILLING)
	drill.visible = true
	particles.emitting = true
	timer.wait_time = 50.0 
	timer.start()
	_start_trigger_sequence("Drill Started") # Trigger 2
	_broadcast_mission_state()

func _on_drilltime_timeout():
	if is_instance_valid(drill): drill.queue_free()
	if is_instance_valid(particles): particles.queue_free()
	anim.play("VaultOpen")
	director.set_phase(director.Phase.LOOTING)
	_start_trigger_sequence("Vault Open") # Trigger 3
	_broadcast_mission_state()

# The Bank Exit Door Trigger
func _on_bank_exit_body_entered(body):
	if multiplayer.is_server() and body.is_in_group("player"):
		if director.current_phase == director.Phase.LOOTING and GameManager.total_loot >= GameManager.min_loot_required:
			director.set_phase(director.Phase.ESCAPE)
			_start_trigger_sequence("Exiting Bank") # Trigger 4
			_broadcast_mission_state()

# --- THE FIX: ESCAPE VAN TRIGGER ---
func _on_area_3d_body_entered(body):
	if multiplayer.is_server() and body.is_in_group("player") and body.state != body.PlayerState.SPECTATING:
		
		# Van is locked if NOT in escape phase OR if there are ANY threats left (waiting OR alive)
		if director.current_phase != director.Phase.ESCAPE or (_cops_left_in_sequence + _active_cops) > 0:
			return

		if GameManager.check_extraction_conditions():
			GameManager.rpc("end_game", true)

# ==============================
# SETUP & SPAWN HELPERS
# ==============================
func _spawn_initial_watchmen():
	for marker in setup_points:
		if not marker is Marker3D or not marker.is_inside_tree(): continue
		var w = watchman_scene.instantiate()
		add_child(w)
		w.global_transform = marker.global_transform
		w.set_multiplayer_authority(multiplayer.get_unique_id())
		w.add_to_group("setup_watchman")

func _check_setup_watchmen_dead():
	if get_tree().get_nodes_in_group("setup_watchman").is_empty():
		_enter_alerted_state()

func _get_spawn_offset(radius: float) -> Vector3:
	return Vector3(randf_range(-radius, radius), 0, randf_range(-radius, radius))

func _get_furthest_or_safe_marker() -> Marker3D:
	var valid_markers = []
	var fallback_marker = null
	var max_dist = -1.0
	for marker in enemy_spawn:
		if not is_instance_valid(marker) or not marker is Marker3D or not marker.is_inside_tree(): continue
		var min_dist_to_players = 9999.0
		for p in director.players_cache:
			if not is_instance_valid(p) or p.state == p.PlayerState.SPECTATING or not p.is_inside_tree(): continue
			min_dist_to_players = min(min_dist_to_players, marker.global_position.distance_to(p.global_position))
		
		if min_dist_to_players > director.safe_spawn_distance: valid_markers.append(marker)
		if min_dist_to_players > max_dist:
			max_dist = min_dist_to_players
			fallback_marker = marker
	return valid_markers.pick_random() if not valid_markers.is_empty() else fallback_marker

# ==============================
# PLAYER SPAWNING & CACHING
# ==============================
func _update_player_cache():
	director.players_cache = get_tree().get_nodes_in_group("player")

func _on_peer_connected(id):
	if multiplayer.is_server():
		spawn_player(id)
	call_deferred("_update_player_cache")

func _on_peer_disconnected(id):
	remove_player(id)
	call_deferred("_update_player_cache")

func _spawn_existing_players():
	spawn_player(multiplayer.get_unique_id())
	for id in multiplayer.get_peers():
		spawn_player(id)

func spawn_player(id):
	if has_node(str(id)): return
	var p = player_scene.instantiate()
	p.name = str(id)
	add_child(p)
	p.global_position = _get_player_spawn()
	p.set_multiplayer_authority(id)

func remove_player(id):
	if has_node(str(id)): get_node(str(id)).queue_free()

func _get_player_spawn() -> Vector3:
	if spawn_points.is_empty(): return Vector3.ZERO
	var marker = spawn_points.pick_random()
	return marker.global_position if marker.is_inside_tree() else Vector3.ZERO

# ==============================
# NETWORKING & UNUSED EVENT CATCHERS
# ==============================
func _broadcast_mission_state():
	rpc("rpc_sync_mission_state", director.current_phase, director.current_wave_index)

@rpc("authority", "call_local")
func rpc_sync_mission_state(p: int, wave_idx: int):
	director.current_phase = p as MissionDirector.Phase
	director.current_wave_index = wave_idx

func _on_phase_changed(_new_phase):
	pass
