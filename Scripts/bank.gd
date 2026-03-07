extends Node3D

# ==============================
# SCENES & COMPONENTS
# ==============================
@export var player_scene : PackedScene
@export var watchman_scene : PackedScene
@export var cop_scene : PackedScene

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
# LOCAL STATE
# ==============================
var _players_spawned := false
@onready var reinforcement_timer : Timer = Timer.new()
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
	
	# Setup Reinforcement Timer
	reinforcement_timer.wait_time = director.assault_spawn_interval
	reinforcement_timer.one_shot = false
	reinforcement_timer.timeout.connect(_on_reinforcements_timeout)
	add_child(reinforcement_timer)

	if multiplayer.is_server():
		_spawn_initial_watchmen()

	if not _players_spawned:
		_players_spawned = true
		_spawn_existing_players()

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	
	_update_player_cache()

	drill.visible = false
	particles.emitting = false

# ==============================
# PROCESS
# ==============================
func _process(delta):
	if multiplayer.is_server():
		match director.current_phase:
			director.Phase.SETUP:
				_check_setup_watchmen_dead()
			_:
				director.update_director(delta)

	_update_ui()

# ==============================
# PERFORMANCE: CACHING
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

# ==============================
# UI
# ==============================
func _on_drama_updated(_val):
	pass # Handled in UI loop for smoothing

func _update_ui():
	var money_needed = GameManager.min_loot_required - GameManager.total_loot
	var enemies_left = GameManager.get_remaining_enemies_count()
	var cap = director.get_max_enemy_cap()

	if money_needed > 0:
		label.text = "Need $" + str(money_needed) + " more"
		label.modulate = Color.RED
		return

	match director.current_phase:
		director.Phase.LOOTING:
			label.text = "ESCAPE NOW!"
			label.modulate = Color.GREEN
		_:
			var status = "HOLDING POSITION"
			if director.current_phase == director.Phase.DRILLING: status = "DRILL IN PROGRESS"
			
			var wave_text = "POLICE ASSAULT IN PROGRESS" if director.is_assault_wave else "ASSAULT FADING..."
			if director.spawn_blocked_by_drama: wave_text = "POLICE REGROUPING"
			
			current_drama_display = lerp(current_drama_display, director.group_drama_level, 0.05)
			var drama_pct = int(current_drama_display * 100)
			
			label.text = status + "\n" + wave_text + "\nEnemies: " + str(enemies_left) + "/" + str(cap) + "\nStress: " + str(drama_pct) + "%"
			
			if director.spawn_blocked_by_drama: label.modulate = Color.CYAN
			elif drama_pct > 70: label.modulate = Color(1.0, 0.4, 0.0)
			else: label.modulate = Color.RED if director.is_assault_wave else Color.YELLOW

# ==============================
# PLAYER SPAWNING
# ==============================
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
# SETUP & MISSION LOGIC
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

func _enter_alerted_state():
	if director.current_phase != director.Phase.SETUP: return
	director.set_phase(director.Phase.ALERTED)
	if multiplayer.is_server():
		_spawn_wave(director.get_initial_wave_count())
		AlertManager.raise_alert(global_transform.origin)
		reinforcement_timer.start()

# ==============================
# SPAWNING SYSTEM
# ==============================
func _on_reinforcements_timeout():
	if not multiplayer.is_server() or director.spawn_blocked_by_drama: return
	
	var current_enemies = GameManager.get_remaining_enemies_count()
	var cap = director.get_max_enemy_cap()
	
	if current_enemies < cap:
		var spawn_count = min(director.get_reinforcement_count(), cap - current_enemies)
		if spawn_count > 0:
			_spawn_wave(spawn_count)
	
	reinforcement_timer.wait_time = director.get_spawn_interval()

func _spawn_wave(total: int):
	for i in range(total):
		var marker = _get_furthest_or_safe_marker()
		if not marker: return
		var cop = cop_scene.instantiate()
		cop.global_position = marker.global_position + _get_spawn_offset(1.5)
		add_child(cop)
		cop.set_multiplayer_authority(multiplayer.get_unique_id())
		await get_tree().create_timer(0.2).timeout

func _get_spawn_offset(radius: float) -> Vector3:
	return Vector3(randf_range(-radius, radius), 0, randf_range(-radius, radius))

func _get_furthest_or_safe_marker() -> Marker3D:
	var valid_markers = []
	var fallback_marker = null
	var max_dist = -1.0
	for marker in enemy_spawn:
		if not marker is Marker3D: continue
		var min_dist_to_players = 9999.0
		for p in director.players_cache:
			if not is_instance_valid(p) or p.state == p.PlayerState.SPECTATING: continue
			min_dist_to_players = min(min_dist_to_players, marker.global_position.distance_to(p.global_position))
		if min_dist_to_players > director.safe_spawn_distance: valid_markers.append(marker)
		if min_dist_to_players > max_dist:
			max_dist = min_dist_to_players
			fallback_marker = marker
	return valid_markers.pick_random() if not valid_markers.is_empty() else fallback_marker

# ==============================
# MISSION OBJECTIVES
# ==============================
func plant():
	if multiplayer.is_server() and director.current_phase == director.Phase.ALERTED:
		rpc("sync_start_drill")

@rpc("authority", "call_local")
func sync_start_drill():
	director.set_phase(director.Phase.DRILLING)
	drill.visible = true
	particles.emitting = true
	timer.start()

func _on_drilltime_timeout():
	drill.queue_free()
	particles.queue_free()
	anim.play("VaultOpen")
	director.set_phase(director.Phase.LOOTING)

func _on_area_3d_body_entered(body):
	if multiplayer.is_server() and body.is_in_group("player") and body.state != body.PlayerState.SPECTATING:
		if GameManager.check_extraction_conditions():
			GameManager.rpc("end_game", true)
