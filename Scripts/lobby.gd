extends Control

# NODES
@onready var status_label = $PanelContainer/VBoxContainer/StatusLabel
@onready var name_input = $PanelContainer/VBoxContainer/NameInput # NEW NODE
@onready var code_input = $PanelContainer/VBoxContainer/CodeInput
@onready var start_btn = $PanelContainer/VBoxContainer/StartBtn
@onready var player_list_label = $PanelContainer/VBoxContainer/PlayerListLabel # NEW NODE

func _ready():
	start_btn.hide()
	NetworkManager.connected_to_server.connect(_on_connected)
	NetworkManager.connection_failed.connect(_on_fail)
	NetworkManager.player_list_updated.connect(_on_player_list_update)
	NetworkManager.game_error.connect(_on_error)

# 1. CONNECT
func _on_button_pressed(): 
	if name_input.text == "":
		status_label.text = "Enter a name first!"
		return

	status_label.text = "Connecting..."
	NetworkManager.connect_to_signaling(name_input.text)

func _on_connected(my_id):
	status_label.text = "Connected! ID: " + str(my_id)

func _on_fail():
	status_label.text = "Failed to connect."

func _on_error(msg):
	status_label.text = msg

# 2. CREATE ROOM
func _on_create_btn_pressed():
	if NetworkManager.my_id == 0: return
	NetworkManager.start_host()
	status_label.text = "Room Created: " + str(NetworkManager.my_id)
	start_btn.show()

# 3. JOIN ROOM
func _on_join_btn_pressed():
	if code_input.text == "": return
	status_label.text = "Joining..."
	NetworkManager.join_game(code_input.text)

# 4. START
func _on_start_btn_pressed():
	rpc("start_game_rpc")

@rpc("any_peer", "call_local")
func start_game_rpc():
	NetworkManager.start_game_scene()

# 5. UPDATE UI LIST
func _on_player_list_update(players):
	var txt = "Lobby Members:\n"
	for id in players:
		txt += "• " + players[id] + " (" + str(id) + ")\n"
	player_list_label.text = txt
