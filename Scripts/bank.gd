extends Node3D

@export var player_scene : PackedScene
@onready var spawn_points := $SpawnPoints.get_children()
@onready var anim = $bank/AnimationPlayer
@onready var drill = $bank/drill
@onready var particles = $bank/GPUParticles3D
@onready var timer = $bank/drilltime

var current_state = 0

func _ready():
	# Spawn self
	spawn_player(multiplayer.get_unique_id())
	
	# Spawn current peers
	for id in multiplayer.get_peers():
		spawn_player(id)
	
	# Listen for connections/disconnections
	multiplayer.peer_connected.connect(spawn_player)
	multiplayer.peer_disconnected.connect(remove_player)
	
	anim.play("RESET")
	drill.visible = false
	particles.emitting = false

func spawn_player(id):
	var p = player_scene.instantiate()
	p.name = str(id)
	var spawn_pos = get_spawn_point()
	p.position = spawn_pos

	add_child(p)

func remove_player(id):
	if has_node(str(id)):
		get_node(str(id)).queue_free()
		print("Player " + str(id) + " removed from scene.")
		
func get_spawn_point() -> Vector3:
	if spawn_points.size() == 0:
		push_error("No spawn points found!")
		return Vector3.ZERO

	# Random spawn point
	var sp = spawn_points[randi() % spawn_points.size()]
	return sp.global_position

func plant():
	# If Closed -> Request to Start Drilling
	if current_state == 0:
		rpc("sync_start_drill")
		

@rpc("any_peer", "call_local")
func sync_start_drill():
	# Security check: Don't start if already open or drilling
	if current_state != 0: return 
	
	current_state = 1 # Set state to Drilling
	
	# Visuals
	drill.visible = true
	particles.emitting = true
	timer.start()

func _on_drilltime_timeout() -> void:
	drill.queue_free()
	particles.queue_free()
	anim.play("VaultOpen")
