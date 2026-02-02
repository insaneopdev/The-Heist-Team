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
# CONTROL FLAGS
# ==============================
var enemies_spawned := false
var _players_spawned := false

# ==============================
# READY
# ==============================
func _ready():
	randomize()

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
		_spawn_enemy_set()
		AlertManager.raise_alert(global_transform.origin)

# ==============================
# ENEMY SET SPAWNING (FIXED)
# ==============================
func _get_enemy_set_count() -> int:
	var players := get_tree().get_nodes_in_group("player").size()

	if players <= 2:
		return 6
	elif players <= 4:
		return 10
	else:
		return 14

func _get_spawn_offset(radius := 5.0) -> Vector3:
	return Vector3(
		randf_range(-radius, radius),
		0.0,
		randf_range(-radius, radius)
	)

func _spawn_enemy_set():
	if enemies_spawned:
		return

	enemies_spawned = true
	var total := _get_enemy_set_count()
	var spawned := 0

	while spawned < total:
		for marker in enemy_spawn:
			if spawned >= total:
				break
			if not marker is Marker3D:
				continue
			if not marker.is_inside_tree():
				continue

			var cop = cop_scene.instantiate()
			add_child(cop)

			cop.global_position = marker.global_position + _get_spawn_offset(5.0)
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
