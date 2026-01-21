extends Node

# SIGNALS
signal money_updated(total_amount)
signal game_ended(is_success)

# SETTINGS
var min_loot_required = 5000
var total_loot = 0

# PLAYER STATS
var player_stats = {}

# ENEMY AUTHORITY
var enemies_spawned := 0
var enemies_alive := 0

func _ready():
	reset_game_data()

func reset_game_data():
	total_loot = 0
	player_stats.clear()
	enemies_spawned = 0
	enemies_alive = 0

	if multiplayer.has_multiplayer_peer():
		var my_id = multiplayer.get_unique_id()
		register_player(my_id, _get_player_name(my_id))

# ------------------------
# PLAYER NAME RESOLUTION
# ------------------------
func _get_player_name(id):
	if NetworkManager.connected_players.has(id):
		return NetworkManager.connected_players[id]

	if id == 1 and NetworkManager.connected_players.has(NetworkManager.host_signaling_id):
		return NetworkManager.connected_players[NetworkManager.host_signaling_id]

	return "Player " + str(id)

# ------------------------
# PLAYER STATS
# ------------------------
func register_player(id, p_name):
	if not player_stats.has(id):
		player_stats[id] = { "kills": 0, "loot": 0, "name": p_name }
	else:
		player_stats[id]["name"] = p_name

func add_loot(id, amount):
	total_loot += amount
	money_updated.emit(total_loot)

	register_player(id, _get_player_name(id))
	player_stats[id]["loot"] += amount

func add_kill(id):
	register_player(id, _get_player_name(id))
	player_stats[id]["kills"] += 1

# ------------------------
# ENEMY AUTHORITY (FIXED)
# ------------------------
func register_enemy():
	enemies_spawned += 1
	enemies_alive += 1

func enemy_died():
	enemies_alive = max(enemies_alive - 1, 0)

# ------------------------
# EXTRACTION LOGIC (AUTHORITATIVE)
# ------------------------
func check_extraction_conditions() -> bool:
	if total_loot < min_loot_required:
		return false

	if enemies_alive > 0:
		return false

	return true

func get_remaining_enemies_count() -> int:
	return enemies_alive

# ------------------------
# GAME END
# ------------------------
@rpc("any_peer", "call_local")
func end_game(success: bool):
	game_ended.emit(success)

	var end_screen = load("res://Scenes/end_screen.tscn").instantiate()
	get_tree().root.add_child(end_screen)

	if get_tree().current_scene:
		get_tree().current_scene.queue_free()

	get_tree().current_scene = end_screen
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
