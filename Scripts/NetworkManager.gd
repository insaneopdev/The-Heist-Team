extends Node

# CONFIGURATION
const SIGNALING_URL = "wss://the-heist-team.onrender.com/" 
const LOBBY_SCENE = "res://Scenes/Lobby.tscn" 
const GAME_SCENE = "res://Scenes/bank.tscn"

var ws = WebSocketPeer.new()
var rtc_peer = WebRTCMultiplayerPeer.new()

# STATE
var my_id = 0
var my_name = "Unknown" 
var host_signaling_id = 0 # The Signaling ID of the Room Owner
var peers = {} 
var connected_players = {} 

# SIGNALS
signal connected_to_server(my_id)
signal player_list_updated(players_dict)
signal game_started
signal game_error(msg)

func _ready():
	multiplayer.peer_connected.connect(_on_mp_peer_connected)
	multiplayer.peer_disconnected.connect(_on_mp_peer_disconnected)
	connect_to_signaling()

func _process(_delta):
	ws.poll()
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		while ws.get_available_packet_count():
			parse_signaling_message()

# --- 1. SIGNALING ---
func connect_to_signaling():
	print("Auto-connecting...")
	ws.connect_to_url(SIGNALING_URL)

func parse_signaling_message():
	var packet = ws.get_packet().get_string_from_utf8()
	var data = JSON.parse_string(packet)
	if not data: return

	if data.has("type"):
		match data["type"]:
			"id":
				my_id = int(data["id"])
				connected_to_server.emit(my_id) 
			
			"join_request":
				if multiplayer.is_server():
					var sender_id = int(data["sender"])
					var sender_name = data.get("name", "Unknown")
					connected_players[sender_id] = sender_name
					broadcast_player_list()
					create_peer(sender_id)
			
			"lobby_update":
				var new_list = data["players"]
				connected_players.clear()
				for k in new_list:
					connected_players[int(k)] = new_list[k]
				player_list_updated.emit(connected_players)

			"offer":
				var sender_id = int(data["sender"])
				if not peers.has(sender_id): create_peer(sender_id)
				peers[sender_id].set_remote_description("offer", data["sdp"])
			
			"answer":
				var sender_id = int(data["sender"])
				if peers.has(sender_id): peers[sender_id].set_remote_description("answer", data["sdp"])
			
			"candidate":
				var sender_id = int(data["sender"])
				if peers.has(sender_id): peers[sender_id].add_ice_candidate(data["mid"], data["index"], data["sdp"])

# --- 2. LOBBY ACTIONS ---

func start_host(player_name):
	my_name = player_name
	rtc_peer.create_server()
	multiplayer.multiplayer_peer = rtc_peer
	
	# FIX: Save my ID as the Host ID, so we can map "1" to this later
	host_signaling_id = my_id 
	
	connected_players.clear()
	connected_players[my_id] = my_name 
	player_list_updated.emit(connected_players)

func join_game(target_code, player_name):
	my_name = player_name
	var target_id = int(target_code)
	
	# FIX: Save target as Host ID
	host_signaling_id = target_id 
	
	rtc_peer.create_client(my_id)
	multiplayer.multiplayer_peer = rtc_peer
	send_signaling_msg({"type": "join_request", "target": target_id, "name": my_name})

func broadcast_player_list():
	for pid in connected_players:
		if pid == my_id: continue 
		send_signaling_msg({"type": "lobby_update", "target": pid, "players": connected_players})
	player_list_updated.emit(connected_players)

func start_game_scene():
	var map = load(GAME_SCENE).instantiate()
	get_tree().root.add_child(map)
	get_tree().current_scene.queue_free()
	get_tree().current_scene = map
	game_started.emit()

func return_to_lobby(reason=""):
	peers.clear()
	connected_players.clear()
	multiplayer.multiplayer_peer = null
	rtc_peer = WebRTCMultiplayerPeer.new() 
	
	if get_tree().root.get_child_count() > 0:
		get_tree().root.get_child(get_tree().root.get_child_count() - 1).queue_free()
	
	var lobby = load(LOBBY_SCENE).instantiate()
	get_tree().root.add_child(lobby)
	get_tree().current_scene = lobby
	if reason != "": game_error.emit(reason)

# --- 3. PEER SETUP ---
func _on_mp_peer_disconnected(id):
	if id == 1: return_to_lobby("Host closed the room.")

func _on_mp_peer_connected(_id): pass

func create_peer(signaling_id):
	var p = WebRTCPeerConnection.new()
	p.initialize({"iceServers": [ { "urls": ["stun:stun.l.google.com:19302"] } ]})
	p.session_description_created.connect(self._on_session_description_created.bind(signaling_id))
	p.ice_candidate_created.connect(self._on_ice_candidate_created.bind(signaling_id))
	
	var mp_id = signaling_id
	if not multiplayer.is_server() and signaling_id == host_signaling_id: mp_id = 1
	
	rtc_peer.add_peer(p, mp_id)
	peers[signaling_id] = p
	if multiplayer.is_server(): p.create_offer()

func _on_session_description_created(type, sdp, target):
	peers[target].set_local_description(type, sdp)
	send_signaling_msg({ "type": type, "target": target, "sdp": sdp })

func _on_ice_candidate_created(mid, index, sdp, target):
	send_signaling_msg({ "type": "candidate", "target": target, "mid": mid, "index": index, "sdp": sdp })

func send_signaling_msg(data):
	ws.put_packet(JSON.stringify(data).to_utf8_buffer())
