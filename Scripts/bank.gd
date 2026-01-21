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

@onready var spawn_timer := $EnemySpawnTimer
@onready var anim = $NavigationRegion3D/bank/AnimationPlayer
@onready var drill = $NavigationRegion3D/bank/drill
@onready var particles = $NavigationRegion3D/bank/GPUParticles3D
@onready var timer = $NavigationRegion3D/bank/drilltime
@onready var label = $Area3D/Label3D

# ==============================
# BANK PHASES
# ==============================
# 0 = SETUP | 1 = ALERTED | 2 = DRILLING | 3 = LOOTING
var current_state := 0

# ==============================
# ENEMY CONTROL (SINGLE AUTHORITY)
# ==============================
var max_enemies := 0
var spawned_count := 0
var alive_count := 0
var spawn_active := false

var _players_spawned := false

# ==============================
# READY
# ==============================
func _ready():
	randomize()

	if multiplayer.is_server():
		_spawn_initial_watchmen()
		spawn_timer.timeout.connect(_try_spawn)

	if not _players_spawned:
		_players_spawned = true
		_spawn_existing_players()

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(remove_player)

	spawn_timer.stop()
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

	if money_needed > 0:
		label.text = "Need $" + str(money_needed) + " more"
		label.modulate = Color.RED
	elif enemies_left > 0:
		label.text = "Eliminate " + str(enemies_left) + " Enemies!"
		label.modulate = Color.ORANGE
	else:
		label.text = "Get into Escape!"
		label.modulate = Color.GREEN

# ==============================
# PLAYER SPAWNING
# ==============================
func _spawn_existing_players():
	spawn_player(multiplayer.get_unique_id())
	for id in multiplayer.get_peers():
		spawn_player(id)

func _on_peer_connected(id):
	spawn_player(id)

func spawn_player(id):
	if has_node(str(id)):
		return

	var p = player_scene.instantiate()
	p.name = str(id)
	p.global_position = _get_player_spawn()
	add_child(p)

func remove_player(id):
	if has_node(str(id)):
		get_node(str(id)).queue_free()

func _get_player_spawn() -> Vector3:
	if spawn_points.is_empty():
		return Vector3.ZERO
	return spawn_points.pick_random().global_position

# ==============================
# SETUP WATCHMEN
# ==============================
func _spawn_initial_watchmen():
	for marker in setup_points:
		if marker is Marker3D:
			var w = watchman_scene.instantiate()
			w.global_transform = marker.global_transform
			w.set_multiplayer_authority(multiplayer.get_unique_id())
			add_child(w)
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
		_start_enemy_encounter()
		AlertManager.raise_alert(global_transform.origin)

# ==============================
# ENEMY SPAWNING (FINITE & SAFE)
# ==============================
func _get_enemy_set_count() -> int:
	var players := get_tree().get_nodes_in_group("player").size()
	if players <= 2:
		return 6
	elif players <= 4:
		return 10
	return 14

func _start_enemy_encounter():
	max_enemies = _get_enemy_set_count()
	spawned_count = 0
	alive_count = 0
	spawn_active = true
	spawn_timer.start(1.5)

func _try_spawn():
	if not spawn_active:
		return

	if spawned_count >= max_enemies:
		spawn_active = false
		spawn_timer.stop()
		return

	if alive_count >= 3:
		return

	_spawn_enemy()

func _spawn_enemy():
	if enemy_spawn.is_empty():
		return

	var marker = enemy_spawn.pick_random()
	if not marker is Marker3D:
		return

	var cop = cop_scene.instantiate()
	cop.global_position = marker.global_position + _get_spawn_offset(5.0)
	cop.set_multiplayer_authority(multiplayer.get_unique_id())
	add_child(cop)

	spawned_count += 1
	alive_count += 1

	# 🔒 SINGLE SOURCE OF TRUTH
	GameManager.register_enemy()

	# Enemy MUST emit: died(killer_id)
	cop.died.connect(_on_enemy_died)

func _on_enemy_died(killer_id):
	alive_count = max(alive_count - 1, 0)
	GameManager.enemy_died()
	GameManager.add_kill(killer_id)

	if spawned_count == max_enemies and alive_count == 0:
		print("BANK ENCOUNTER CLEARED")

func _get_spawn_offset(radius := 5.0) -> Vector3:
	return Vector3(
		randf_range(-radius, radius),
		0,
		randf_range(-radius, radius)
	)

# ==============================
# BANK DRILL
# ==============================
func plant():
	if current_state == 1:
		rpc("sync_start_drill")

@rpc("any_peer", "call_local")
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
