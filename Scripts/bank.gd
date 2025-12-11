extends Node3D

@export var player_scene : PackedScene

func _ready():
	# Spawn self
	spawn_player(multiplayer.get_unique_id())
	
	# Spawn current peers
	for id in multiplayer.get_peers():
		spawn_player(id)
	
	# Listen for connections/disconnections
	multiplayer.peer_connected.connect(spawn_player)
	multiplayer.peer_disconnected.connect(remove_player)

func spawn_player(id):
	var p = player_scene.instantiate()
	p.name = str(id)
	# Add Spawn Point Logic here...
	p.position = Vector3(0, 5, 0) 
	add_child(p)

func remove_player(id):
	if has_node(str(id)):
		get_node(str(id)).queue_free()
		print("Player " + str(id) + " removed from scene.")
