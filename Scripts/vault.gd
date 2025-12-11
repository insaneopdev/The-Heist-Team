extends StaticBody3D

# STATES: 0 = Closed, 1 = Drilling, 2 = Lootable, 3 = Looted
var current_state = 0 

@onready var anim = $vault/AnimationPlayer
@onready var drill_node = $vault/drill
@onready var particles = $GPUParticles3D
@onready var timer = $drilltime
@onready var gold = $gold

func _ready():
	# Ensure default visuals
	anim.play("RESET")
	drill_node.visible = false
	particles.emitting = false
	gold.visible = true

# This function is called when a player looks at the vault and presses Interact
func plant():
	# If Closed -> Request to Start Drilling
	if current_state == 0:
		rpc("sync_start_drill")
		
	# If Lootable -> Request to Grab Loot
	elif current_state == 2:
		rpc("sync_grab_loot")

# --- DRILLING SYNC ---

@rpc("any_peer", "call_local")
func sync_start_drill():
	# Security check: Don't start if already open or drilling
	if current_state != 0: return 
	
	current_state = 1 # Set state to Drilling
	
	# Visuals
	drill_node.visible = true
	particles.emitting = true
	timer.start()

func _on_drilltime_timeout() -> void:
	# This runs automatically on everyone's PC when their timer finishes
	drill_node.visible = false
	particles.emitting = false
	anim.play("doorAction")
	
	# Update state to Lootable (Ready for pickup)
	current_state = 2


@rpc("any_peer", "call_local")
func sync_grab_loot():
	# Security check: Can only loot if door is open
	if current_state != 2: return 
	
	current_state = 3 # Set state to Looted
	gold.visible = false
	
	# Only the person who clicked acts as the "trigger"
	# But the money RPC is sent to everyone by the GameManager
	if multiplayer.get_unique_id() == multiplayer.get_remote_sender_id():
		# Add $10,000 to the team pot
		GameManager.rpc("add_money", 10000)
