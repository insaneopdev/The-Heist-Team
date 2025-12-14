extends StaticBody3D

# STATES: 0 = Closed, 1 = Drilling, 2 = Lootable, 3 = Looted
var current_state = 0 
var vault_loot_amount = 50000

@onready var anim = $vault/AnimationPlayer
@onready var drill_node = $vault/drill
@onready var particles = $GPUParticles3D
@onready var timer = $drilltime
@onready var gold = $gold

func _ready():
	# Reset Visuals
	anim.play("RESET")
	drill_node.visible = false
	particles.emitting = false
	gold.visible = true

# Called by Player
func plant():
	if current_state == 0:
		rpc("sync_start_drill")
	
	elif current_state == 2:
		rpc("sync_grab_loot")

# --- DRILLING LOGIC ---

@rpc("any_peer", "call_local")
func sync_start_drill():
	if current_state != 0: return 
	
	current_state = 1 # Drilling
	
	# Visuals
	drill_node.visible = true
	particles.emitting = true
	
	# Start Timer (Ensure 'One Shot' is ON in Inspector)
	timer.start()

func _on_drilltime_timeout() -> void:
	# Timer finished? Open the door!
	drill_node.visible = false
	particles.emitting = false
	anim.play("doorAction")
	
	current_state = 2 # Lootable

# --- LOOTING LOGIC ---

@rpc("any_peer", "call_local")
func sync_grab_loot():
	if current_state != 2: return 
	
	current_state = 3 # Looted
	gold.visible = false
	
	# 1. Identify WHO clicked the vault
	var collector_id = multiplayer.get_remote_sender_id()
	
	# 2. Add Money to Stats
	GameManager.add_loot(collector_id, vault_loot_amount)
