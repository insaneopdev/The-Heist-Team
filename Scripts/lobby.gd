extends Control

# NODES
@onready var status_label = $StatusLabel
@onready var name_input = $NameInput
@onready var code_input = $CodeInput
@onready var start_btn = $StartBtn
@onready var player_list_label = $PlayerListLabel

var id

func _ready():
	start_btn.hide()
	NetworkManager.connected_to_server.connect(_on_connected)
	NetworkManager.player_list_updated.connect(_on_player_list_update)
	
	status_label.text = "Auto-Connecting..."

func _process(delta: float) -> void:
	$SubViewportContainer/SubViewport/bean/NameLabel.text = name_input.text

func _on_connected(my_id):
	status_label.text = "Connected! Your ID: " + str(my_id)
	id = my_id

# 1. CREATE ROOM
func _on_create_btn_pressed():
	if name_input.text == "":
		status_label.text = "Enter Name First!"
		return
	if NetworkManager.my_id == 0: 
		status_label.text = "Wait for Connection..."
		return
		
	# Pass Name to NetworkManager
	NetworkManager.start_host(name_input.text)
	
	status_label.text = "Room Ready! Room ID: " + str(id)
	start_btn.show()

# 2. JOIN ROOM
func _on_join_btn_pressed():
	if name_input.text == "":
		status_label.text = "Enter Name First!"
		return
	if code_input.text == "":
		status_label.text = "Enter Code!"
		return

	status_label.text = "Joining..."
	# Pass Name to NetworkManager
	NetworkManager.join_game(code_input.text, name_input.text)

# 3. START GAME
func _on_start_btn_pressed():
	rpc("start_game_rpc")

@rpc("any_peer", "call_local")
func start_game_rpc():
	NetworkManager.start_game_scene()

func _on_player_list_update(players):
	var txt = "Lobby Members:\n"
	for id in players:
		txt += "• " + players[id] + " (" + str(id) + ")\n"
	player_list_label.text = txt
