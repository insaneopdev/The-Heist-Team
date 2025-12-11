extends Node

# Shared Team Money
var team_money = 0

signal money_updated(new_amount)

# Call this to add money (Syncs to everyone)
@rpc("any_peer", "call_local")
func add_money(amount):
	team_money += amount
	money_updated.emit(team_money)
	print("Team Money: $", team_money)

# Reset money when starting a new game
func reset_money():
	team_money = 0
	money_updated.emit(0)
