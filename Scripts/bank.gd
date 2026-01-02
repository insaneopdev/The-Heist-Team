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
@onready var setup := $setup.get_children()               # initial watchmen
@onready var enemy_spawn := $enemy_spawn.get_children()   # combat spawns

@onready var anim = $NavigationRegion3D/bank/AnimationPlayer
@onready var drill = $NavigationRegion3D/bank/drill
@onready var particles = $NavigationRegion3D/bank/GPUParticles3D
@onready var timer = $NavigationRegion3D/bank/drilltime
@onready var label = $Area3D/Label3D

# ==============================
# BANK STATE
# ==============================
# 0 = closed
# 1 = drilling
# 2 = open (optional future)
var current_state := 0

# ==============================
# SPAWN DIRECTOR SETTINGS
# ==============================
@export var max_enemies_alive := 12
@export var spawn_interval := 4.0
@export var ramp_after_seconds := 60.0

@export var cop_weight := 0.75
@export var watchman_weight := 0.25

var chaos_active := false
var spawn_timer := 0.0
var combat_time := 0.0

# ==============================
# READY
# ==============================
func _ready():
	if multiplayer.is_server():
		_spawn_initial_watchmen()

	# Player spawning
	spawn_player(multiplayer.get_unique_id())
	for id in multiplayer.get_peers():
		spawn_player(id)

	multiplayer.peer_connected.connect(spawn_player)
	multiplayer.peer_disconnected.connect(remove_player)

	drill.visible = false
	particles.emitting = false

# ==============================
# PROCESS
# ==============================
func _process(delta):
	if multiplayer.is_server() and chaos_active:
		_update_spawn_director(delta)

	_update_ui()

# ==============================
# UI LOGIC
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
func spawn_player(id):
	var p = player_scene.instantiate()
	p.name = str(id)
	p.position = _get_player_spawn()
	add_child(p)

func remove_player(id):
	if has_node(str(id)):
		get_node(str(id)).queue_free()

func _get_player_spawn() -> Vector3:
	if spawn_points.is_empty():
		return Vector3.ZERO
	return spawn_points.pick_random().global_position

# ==============================
# BANK INTERACTION
# ==============================
func plant():
	if current_state == 0:
		rpc("sync_start_drill")

@rpc("any_peer", "call_local")
func sync_start_drill():
	if current_state != 0:
		return

	current_state = 1
	chaos_active = true

	drill.visible = true
	particles.emitting = true
	timer.start()

func _on_drilltime_timeout():
	drill.queue_free()
	particles.queue_free()
	anim.play("VaultOpen")

# ==============================
# INITIAL WATCHMEN
# ==============================
func _spawn_initial_watchmen():
	for marker in setup:
		if not marker is Marker3D:
			continue

		var w = watchman_scene.instantiate()
		w.global_transform = marker.global_transform
		w.set_multiplayer_authority(1)
		add_child(w)

# ==============================
# SPAWN DIRECTOR (CORE SYSTEM)
# ==============================
func _update_spawn_director(delta):
	combat_time += delta
	spawn_timer -= delta

	var interval := spawn_interval
	if combat_time > ramp_after_seconds:
		interval *= 0.6   # faster spawns later

	if spawn_timer > 0:
		return

	if GameManager.get_remaining_enemies_count() >= max_enemies_alive:
		return

	spawn_timer = interval
	_spawn_enemy()

# ==============================
# ENEMY SPAWNING
# ==============================
func _spawn_enemy():
	if enemy_spawn.is_empty():
		return

	var marker: Marker3D = enemy_spawn.pick_random()
	if not _is_spawn_safe(marker.global_position):
		return

	var roll := randf()
	if roll < cop_weight:
		_spawn_cop(marker)
	else:
		_spawn_watchman(marker)

func _spawn_cop(marker: Marker3D):
	var cop = cop_scene.instantiate()
	cop.global_transform = marker.global_transform
	cop.set_multiplayer_authority(1)
	add_child(cop)

func _spawn_watchman(marker: Marker3D):
	var w = watchman_scene.instantiate()
	w.global_transform = marker.global_transform
	w.set_multiplayer_authority(1)
	add_child(w)

# ==============================
# ANTI-CAMPING SPAWN SAFETY
# ==============================
func _is_spawn_safe(pos: Vector3) -> bool:
	for p in get_tree().get_nodes_in_group("player"):
		if pos.distance_to(p.global_position) < 6.0:
			return false
	return true

# ==============================
# EXTRACTION CHECK
# ==============================
func _on_area_3d_body_entered(body):
	if not multiplayer.is_server():
		return

	if body.is_in_group("player") and body.state != body.PlayerState.SPECTATING:
		if GameManager.check_extraction_conditions():
			GameManager.rpc("end_game", true)
