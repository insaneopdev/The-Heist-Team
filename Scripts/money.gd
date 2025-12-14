extends StaticBody3D

@export var amount = 1000 # Configurable amount per stack

func loot():
	# Trigger the RPC on everyone (including self)
	rpc("grab_loot")

@rpc("any_peer", "call_local")
func grab_loot():
	# 1. Identify WHO clicked this money
	var collector_id = multiplayer.get_remote_sender_id()
	
	# 2. Add to Team Total & Individual Stats
	# (Since this RPC runs on everyone's PC, everyone's UI updates instantly)
	GameManager.add_loot(collector_id, amount)
	
	# 3. Delete the object
	queue_free()
