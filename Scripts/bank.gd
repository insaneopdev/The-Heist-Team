extends Node3D

@export var player_scene : PackedScene
@onready var spawn_points := $SpawnPoints.get_children()



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
