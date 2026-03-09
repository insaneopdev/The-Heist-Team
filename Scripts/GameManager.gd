extends Node

# SIGNALS
signal money_updated(total_amount)
signal game_ended(is_success)
signal enemy_died_signal()

# SETTINGS
var min_loot_required = 5000 
var total_loot = 0

# STATS TRACKING: { peer_id: { "kills": 0, "loot": 0, "name": "Name" } }
var player_stats = {} 

func _ready():
	reset_game_data()

func reset_game_data():
	total_loot = 0
	player_stats.clear()
	
	# Initial Registration (Try to get name, default to "Unknown" if loading)
	if multiplayer.has_multiplayer_peer():
		var my_id = multiplayer.get_unique_id()
		var my_name = _get_player_name(my_id)
		register_player(my_id, my_name)

# --- HELPER TO GET REAL NAMES ---
func _get_player_name(id):
	# 1. Try to find name in NetworkManager's list
	if NetworkManager.connected_players.has(id):
		return NetworkManager.connected_players[id]
	
	# 2. Fallback for Host (Host is always ID 1 to the server)
	if id == 1 and NetworkManager.connected_players.has(NetworkManager.host_signaling_id):
		return NetworkManager.connected_players[NetworkManager.host_signaling_id]
		
	return "Player " + str(id)

# --- STATS LOGIC ---
func register_player(id, p_name):
	if not player_stats.has(id):
		player_stats[id] = { "kills": 0, "loot": 0, "name": p_name }
	else:
		# Update name if we learned it later
		player_stats[id]["name"] = p_name

func add_loot(id, amount):
	total_loot += amount
	money_updated.emit(total_loot)
	
	var p_name = _get_player_name(id)
	register_player(id, p_name) # Ensure registered with correct name
	player_stats[id]["loot"] += amount

func add_kill(id):
	var p_name = _get_player_name(id)
	register_player(id, p_name) # Ensure registered with correct name
	player_stats[id]["kills"] += 1

func register_enemy(): pass # No longer needed, we count group members directly
func enemy_died(): 
	enemy_died_signal.emit()

# --- GAME OVER LOGIC (FIXED) ---
func check_extraction_conditions() -> bool:
	# 1. Check Money
	if total_loot < min_loot_required:
		return false
		
	# 2. Check Enemies (Count directly from Tree)
	# var enemies_alive = get_tree().get_nodes_in_group("enemy").size()
	# if enemies_alive > 0:
	# 	return false
		
	return true

func get_remaining_enemies_count() -> int:
	return get_tree().get_nodes_in_group("enemy").size()

@rpc("any_peer", "call_local")
func end_game(success: bool):
	game_ended.emit(success)
	var end_screen = load("res://Scenes/end_screen.tscn").instantiate()
	get_tree().root.add_child(end_screen)
	if get_tree().current_scene:
		get_tree().current_scene.queue_free()
	get_tree().current_scene = end_screen
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
