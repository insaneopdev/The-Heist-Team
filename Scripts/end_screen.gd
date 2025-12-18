extends Control

@onready var title = $Title
@onready var stats_label = $Stats
@onready var mvp_label = $MVP
@onready var lobby_btn = $LobbyBtn

func _ready():
	# Decide MVP
	calculate_stats()
	
	# Only Host can click "Return to Lobby" to sync everyone
	if not multiplayer.is_server():
		lobby_btn.hide()

func calculate_stats():
	var best_score = -1
	var best_name = ""
	var report = ""
	
	for id in GameManager.player_stats:
		var p = GameManager.player_stats[id]
		var score = p["loot"] + (p["kills"] * 500) # 500 points per kill value
		
		report += p["name"] + ": $" + str(p["loot"]) + " | Kills: " + str(p["kills"]) + "\n"
		
		if score > best_score:
			best_score = score
			best_name = p["name"]
	
	title.text = "MISSION SUCCESS" if GameManager.total_loot >= GameManager.min_loot_required else "FAILURE"
	stats_label.text = report
	mvp_label.text = "MVP: " + best_name

func _on_lobby_btn_pressed():
	# Tell NetworkManager to reset
	rpc("return_to_lobby_rpc")

@rpc("call_local", "any_peer")
func return_to_lobby_rpc():
	GameManager.reset_game_data()
	NetworkManager.return_to_lobby()
