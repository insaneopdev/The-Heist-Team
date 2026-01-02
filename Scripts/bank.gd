extends Node3D

@export var player_scene : PackedScene
@export var watchman_scene : PackedScene
@export var cop_scene : PackedScene 


@onready var spawn_points := $SpawnPoints.get_children()
@onready var anim = $NavigationRegion3D/bank/AnimationPlayer
@onready var drill = $NavigationRegion3D/bank/drill
@onready var particles = $NavigationRegion3D/bank/GPUParticles3D
@onready var timer = $NavigationRegion3D/bank/drilltime
@onready var label = $Area3D/Label3D
@onready var setup = $setup.get_children()


var current_state = 0

func _ready():
	if multiplayer.is_server():
		spawn_watchmen()
	# Spawn self
	spawn_player(multiplayer.get_unique_id())
	
	# Spawn current peers
	for id in multiplayer.get_peers():
		spawn_player(id)
	
	# Listen for connections/disconnections
	multiplayer.peer_connected.connect(spawn_player)
	multiplayer.peer_disconnected.connect(remove_player)
	
	drill.visible = false
	particles.emitting = false
	

func _process(delta):
	var money_needed = GameManager.min_loot_required - GameManager.total_loot
	var enemies_left = GameManager.get_remaining_enemies_count()
	
	# CONDITION 1: NEED MONEY
	if money_needed > 0:
		label.text = "Need $" + str(money_needed) + " more"
		label.modulate = Color.RED
		
	# CONDITION 2: NEED KILLS
	elif enemies_left > 0:
		label.text = "Eliminate " + str(enemies_left) + " Enemies!"
		label.modulate = Color.ORANGE
		
	# CONDITION 3: ESCAPE READY
	else:
		label.text = "Get in to Escape!"
		label.modulate = Color.GREEN

func _on_area_3d_body_entered(body):
	# Only the Host checks the win condition
	if not multiplayer.is_server(): return
	
	if body.is_in_group("player"):
		# Ensure they aren't dead/spectating
		if body.state != body.PlayerState.SPECTATING:
			if GameManager.check_extraction_conditions():
				GameManager.rpc("end_game", true)

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
		

func spawn_watchmen():
	for marker in setup:
		if not marker is Marker3D:
			continue

		var w = watchman_scene.instantiate()
		w.global_transform = marker.global_transform

		# Server owns AI
		w.set_multiplayer_authority(1)

		add_child(w)



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
