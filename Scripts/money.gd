extends StaticBody3D

func loot():
	rpc("grab_loot")

@rpc("any_peer", "call_local")
func grab_loot():
	if multiplayer.get_unique_id() == multiplayer.get_remote_sender_id():
		# Add $10,000 to the team pot
		GameManager.rpc("add_money", 10000)
	
	queue_free()
