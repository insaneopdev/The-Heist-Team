extends Node3D

@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var machine_mesh: MeshInstance3D = $machine 
@onready var win_audio: AudioStreamPlayer3D = $winaudio
@export var win_chance: float = 0.05 # 5% chance to win

const REEL_SURFACES = [4, 5, 6]

var colors = [Color.RED, Color.GREEN, Color.BLUE, Color.YELLOW, Color.PURPLE, Color.ORANGE, Color.WHITE, Color.BLACK]
var is_spinning = false

func _ready():
	randomize()

func interact():
	if is_spinning:
		return 
	
	var final_c1: Color
	var final_c2: Color
	var final_c3: Color
	
	# Roll the dice against your win probability
	if randf() <= win_chance:
		# FORCE A WIN: Pick one color and assign it to all three
		var winning_color = colors.pick_random()
		final_c1 = winning_color
		final_c2 = winning_color
		final_c3 = winning_color
	else:
		# FORCE A LOSS: Pick random colors
		final_c1 = colors.pick_random()
		final_c2 = colors.pick_random()
		final_c3 = colors.pick_random()
		
		# Just in case pure randomness accidentally matches all three, 
		# change the last one to guarantee a loss and keep your win % accurate.
		while final_c1 == final_c2 and final_c2 == final_c3:
			final_c3 = colors.pick_random()
	
	# Tell everyone to start spinning and send the rigged result
	rpc("sync_start_slots", final_c1, final_c2, final_c3)

# 'any_peer' lets any player trigger this. 'call_local' ensures the sender runs it too.
@rpc("any_peer", "call_local")
func sync_start_slots(c1: Color, c2: Color, c3: Color):
	is_spinning = true
	
	if anim_player.has_animation("slot"):
		anim_player.play("slot")
	
	var total_duration = 9.0 
	var elapsed = 0.0
	
	# --- VISUAL SPINNING ---
	# The rapid color changing is just visual flair, so it's fine if this 
	# looks slightly different on everyone's screen while it's moving.
	while elapsed < total_duration:
		var wait_time = lerp(0.05, 0.3, elapsed / total_duration)
		change_random_colors()
		
		await get_tree().create_timer(wait_time).timeout
		elapsed += wait_time
	
	# --- APPLY SYNCHRONIZED RESULT ---
	# The spin is over. Force the displays to show the networked colors.
	set_final_colors(c1, c2, c3)
	check_for_win(c1, c2, c3)
	
	is_spinning = false

func change_random_colors():
	for i in REEL_SURFACES:
		var new_mat = StandardMaterial3D.new()
		new_mat.albedo_color = colors.pick_random()
		machine_mesh.set_surface_override_material(i, new_mat)

func set_final_colors(c1: Color, c2: Color, c3: Color):
	var final_colors_array = [c1, c2, c3]
	for idx in range(3):
		var new_mat = StandardMaterial3D.new()
		new_mat.albedo_color = final_colors_array[idx]
		machine_mesh.set_surface_override_material(REEL_SURFACES[idx], new_mat)

func check_for_win(c1: Color, c2: Color, c3: Color):
	if c1 == c2 and c2 == c3:
		print("Jackpot! Colors match!")
		if win_audio and not win_audio.playing:
			win_audio.play()
	else:
		print("No match. Try again!")
