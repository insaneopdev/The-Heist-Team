extends Node3D

# ==============================
# SCENES
# ==============================
@export var player_scene : PackedScene
@export var watchman_scene : PackedScene
@export var cop_scene : PackedScene

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
# BANK PHASES
# ==============================
# 0 = SETUP
# 1 = ALERTED
# 2 = DRILLING
# 3 = LOOTING
var current_state := 0

# ==============================
# SPAWN SETTINGS (GROUP-BASED BALANCING)
# ==============================
# Small Groups (1-2 Players): 4 Enemies Max
# Medium Groups (3-5 Players): 7 Enemies Max
# Large Groups (6-8 Players): 10 Enemies Max
const REINFORCEMENT_COOLDOWN := 30.0 # Increased for better pacing

# ==============================
# CONTROL FLAGS
# ==============================
var enemies_spawned := false
var _players_spawned := false
@onready var reinforcement_timer : Timer = Timer.new()

# ==============================
# READY
# ==============================
func _ready():
	randomize()

	# Setup Reinforcement Timer
	reinforcement_timer.wait_time = REINFORCEMENT_COOLDOWN
	reinforcement_timer.one_shot = false
	reinforcement_timer.timeout.connect(_on_reinforcements_timeout)
	add_child(reinforcement_timer)

	if multiplayer.is_server():
		_spawn_initial_watchmen()

	if not _players_spawned:
		_players_spawned = true
		_spawn_existing_players()

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(remove_player)

	drill.visible = false
	particles.emitting = false

# ==============================
# PROCESS
# ==============================
func _process(_delta):
	if multiplayer.is_server() and current_state == 0:
		_check_setup_watchmen_dead()

	_update_ui()

# ==============================
# UI
# ==============================
func _update_ui():
	var money_needed = GameManager.min_loot_required - GameManager.total_loot
	var enemies_left = GameManager.get_remaining_enemies_count()
	var cap = _get_max_enemy_cap()

	if money_needed > 0:
		label.text = "Need $" + str(money_needed) + " more"
		label.modulate = Color.RED
	elif enemies_left > 0 or current_state < 3:
		# If we are looting but still have enemies, or waiting for exit
		var status = "HOLDING POSITION"
		if current_state == 2: status = "DRILL IN PROGRESS"
		if current_state == 3: status = "GET TO ESCAPE!"
		
		label.text = status + "\nEnemies: " + str(enemies_left) + "/" + str(cap)
		label.modulate = Color.ORANGE
	else:
		label.text = "ESCAPE NOW!"
		label.modulate = Color.GREEN

# ==============================
# PLAYER SPAWNING (FIXED)
# ==============================
func _spawn_existing_players():
	spawn_player(multiplayer.get_unique_id())
	for id in multiplayer.get_peers():
		spawn_player(id)

func _on_peer_connected(id):
	if multiplayer.is_server():
		spawn_player(id)

func spawn_player(id):
	if has_node(str(id)):
		return

	var p = player_scene.instantiate()
	p.name = str(id)
	add_child(p)

	p.global_position = _get_player_spawn()
	p.set_multiplayer_authority(id)

func remove_player(id):
	if has_node(str(id)):
		get_node(str(id)).queue_free()

func _get_player_spawn() -> Vector3:
	if spawn_points.is_empty():
		return Vector3.ZERO

	var marker = spawn_points.pick_random()
	if not marker.is_inside_tree():
		return Vector3.ZERO

	return marker.global_position

# ==============================
# SETUP WATCHMEN (FIXED)
# ==============================
func _spawn_initial_watchmen():
	for marker in setup_points:
		if not marker is Marker3D:
			continue
		if not marker.is_inside_tree():
			continue

		var w = watchman_scene.instantiate()
		add_child(w)

		w.global_transform = marker.global_transform
		w.set_multiplayer_authority(multiplayer.get_unique_id())
		w.add_to_group("setup_watchman")

func _check_setup_watchmen_dead():
	if get_tree().get_nodes_in_group("setup_watchman").is_empty():
		_enter_alerted_state()

# ==============================
# ALERTED STATE
# ==============================
func _enter_alerted_state():
	if current_state >= 1:
		return

	current_state = 1

	if multiplayer.is_server():
		# Initial first responder wave
		_spawn_wave(_get_initial_wave_count())
		AlertManager.raise_alert(global_transform.origin)
		
		# Start the reinforcement loop
		reinforcement_timer.start()

# ==============================
# STATE-BASED SPAWNING LOGIC
# ==============================

func _get_player_count() -> int:
	return get_tree().get_nodes_in_group("player").size()

func _get_max_enemy_cap() -> int:
	var count = _get_player_count()
	if count <= 2: return 4
	if count <= 5: return 7
	return 10

func _get_initial_wave_count() -> int:
	# Start with half the cap or at least 2
	return max(2, _get_max_enemy_cap() / 2)

func _get_reinforcement_count() -> int:
	# Smaller, more manageable trickle
	var count = _get_player_count()
	if count <= 2: return 1
	if count <= 5: return 2
	return 3

func _on_reinforcements_timeout():
	if not multiplayer.is_server():
		return
		
	# Only spawn if Alerted and below the cap
	var current_enemies = GameManager.get_remaining_enemies_count()
	var cap = _get_max_enemy_cap()
	
	if current_enemies < cap:
		var spawn_count = _get_reinforcement_count()
		# Don't exceed cap
		spawn_count = min(spawn_count, cap - current_enemies)
		
		if spawn_count > 0:
			_spawn_wave(spawn_count)

func _get_spawn_offset(radius := 5.0) -> Vector3:
	return Vector3(
		randf_range(-radius, radius),
		0.0,
		randf_range(-radius, radius)
	)

func _spawn_wave(total: int):
	var spawned := 0
	while spawned < total:
		for marker in enemy_spawn:
			if spawned >= total:
				break
			if not marker is Marker3D: continue
			
			var cop = cop_scene.instantiate()
			add_child(cop)
			cop.global_position = marker.global_position + _get_spawn_offset(6.0)
			cop.set_multiplayer_authority(multiplayer.get_unique_id())
			spawned += 1

# ==============================
# BANK DRILL
# ==============================
func plant():
	if multiplayer.is_server() and current_state == 1:
		sync_start_drill()

@rpc("authority", "call_local")
func sync_start_drill():
	if current_state != 1:
		return

	current_state = 2
	drill.visible = true
	particles.emitting = true
	timer.start()

func _on_drilltime_timeout():
	drill.queue_free()
	particles.queue_free()
	anim.play("VaultOpen")
	current_state = 3

# ==============================
# EXTRACTION
# ==============================
func _on_area_3d_body_entered(body):
	if not multiplayer.is_server():
		return

	if body.is_in_group("player") and body.state != body.PlayerState.SPECTATING:
		if GameManager.check_extraction_conditions():
			GameManager.rpc("end_game", true)
