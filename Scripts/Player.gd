extends CharacterBody3D

# --- NODES RELATION ---
@onready var pivot = $pivot
@onready var mesh = $mesh 
@onready var primary_gun = $pivot/primary_gun
@onready var secondary_gun = $pivot/secondary_gun
@onready var p_muzzle = $pivot/primary_gun/gun_muzzle
@onready var s_muzzle = $pivot/secondary_gun/gun_muzzle
@onready var cam = $pivot/Camera3D
@onready var raycast = $pivot/RayCast3D
@onready var anim = $AnimationPlayer 

# --- UI NODES ---
# Note: These are inside the CanvasLayer
@onready var ui_layer = $CanvasLayer
@onready var money_label = $CanvasLayer/MoneyLabel
@onready var ammo_label = $CanvasLayer/AmmoLabel
@onready var health_bar = $CanvasLayer/HealthBar

# Note: This is the 3D Label above the head
@onready var name_label = $NameLabel

# --- SCENE ---
@export var Bullet_Scene : PackedScene

# --- MOVEMENT SETTINGS ---
@export var walk_speed = 4.0
@export var sprint_speed = 6.0
@export var jump_height = 5.0
@export var crouch_speed = 3.0
var decel_speed := 12.0  
@export var gravity : float = 20.0
@export var mouse_sensitivity := 0.2
@export var max_aim_distance := 1000.0

# --- HEALTH & DEATH SETTINGS ---
var max_health = 10000
var current_health = 10000
var downed_health = 50 

# --- WEAPON SETTINGS ---
var prim_ammo_max = 30; var prim_ammo_current = 30; var prim_fire_rate = 0.2; var prim_spread = 0.05; var prim_recoil = 0.03; var prim_damage = 10
var sec_ammo_max = 6; var sec_ammo_current = 6; var sec_fire_rate = 0.25; var sec_spread = 0.01; var sec_recoil = 0.1; var sec_damage = 40
var is_primary = true; var is_reloading = false; var time_since_last_shot = 0.0; var muzzle = null

# --- FEEL (SHAKE & BOB) ---
var current_shake = 0.0
var shake_decay = 10.0 
var rotation_x := 0.0
var bob_time := 0.0
var original_cam_pos = null
var bob_amount = 0.1
var bob_speed = 10.0

# --- STATE MACHINE ---
enum PlayerState { IDLE, WALK, RUN, CROUCH, AIR, DOWNED, SPECTATING }
var state : PlayerState = PlayerState.IDLE

# --- OTHER VARS ---
var is_crouching = false
var current_speed = 0.0
var stand_scale := Vector3(1, 1, 1)
var crouch_scale := Vector3(1, 0.8, 1)
var downed_scale := Vector3(1, 0.5, 1) 
var crouch_lerp_speed := 10.0
var spectate_target_idx = 0

func _enter_tree(): set_multiplayer_authority(str(name).to_int())

func _ready() -> void:
	# 1. INITIALIZE WEAPONS FOR EVERYONE (Fixes "Always Pistol" bug)
	# This ensures even remote players start with Primary Gun visible
	equip_weapon(true)
	
	# 2. SETUP GROUPS
	add_to_group("player") 
	
	# 3. MOVEMENT SETUP
	floor_max_angle = deg_to_rad(50); floor_snap_length = 0.3
	
	# 4. INITIALIZE HEALTH
	current_health = max_health
	if health_bar: health_bar.max_value = max_health; health_bar.value = current_health

	# 5. SYNC NAMES & MONEY
	money_label.text = "Team Take: $0"
	GameManager.money_updated.connect(update_display)
	NetworkManager.player_list_updated.connect(update_player_name)
	update_player_name(NetworkManager.connected_players)

	# --- REMOTE PLAYER (THEM) ---
	if not is_multiplayer_authority():
		cam.current = false
		set_process_unhandled_input(false)
		
		# CRITICAL FIX: Hide the UI for other players so it doesn't overlap yours
		if ui_layer: ui_layer.hide()
		
		# Ensure their body is visible (so we can shoot them)
		if mesh: mesh.show()
		name_label.show()
		return

	# --- LOCAL PLAYER (ME) ---
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# Hide my own body mesh (FPS view)
	if mesh: mesh.hide()
	# Hide my own name tag
	name_label.hide()
	
	raycast.add_exception(self)
	cam.position.z = 0.2; original_cam_pos = cam.position
	
	# Initial UI Update
	update_ammo_ui()

# --- NAME SYNC ---
func update_player_name(players_dict):
	if state == PlayerState.DOWNED or state == PlayerState.SPECTATING: return
	var my_id = str(name).to_int()
	var lookup_id = my_id
	if my_id == 1: lookup_id = NetworkManager.host_signaling_id
	if players_dict.has(lookup_id): name_label.text = players_dict[lookup_id]
	else: name_label.text = "Player " + str(lookup_id)

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority(): return
	
	if state == PlayerState.SPECTATING:
		spectate_behavior()
		return 

	if state == PlayerState.DOWNED:
		velocity.x = 0; velocity.z = 0; velocity.y -= gravity * delta
		move_and_slide()
		scale = scale.lerp(downed_scale, delta * 5.0)
		return 

	time_since_last_shot += delta
	if not is_reloading:
		weapon_input_logic()
		if Input.is_action_just_pressed("crouch"): is_crouching = !is_crouching
		if Input.is_action_just_pressed("plant"): check_interaction()

	update_state()
	apply_state_effects(delta)
	apply_movement(delta)
	apply_gravity(delta)
	apply_head_bob(delta)
	apply_camera_shake_and_recoil(delta)
	apply_crouch_scale(delta)
	move_and_slide()

# ------------------------------------------------------------------
#  WEAPON LOGIC
# ------------------------------------------------------------------

func weapon_input_logic():
	# Sync Weapon Switch
	if Input.is_action_just_pressed("switch"): 
		rpc("equip_weapon", !is_primary)
		return
		
	if Input.is_action_just_pressed("reload"): reload(); return

	var trying_to_shoot = false
	var current_rate = 0.0

	if is_primary:
		trying_to_shoot = Input.is_action_pressed("shoot")
		current_rate = prim_fire_rate
	else:
		trying_to_shoot = Input.is_action_just_pressed("shoot")
		current_rate = sec_fire_rate
	
	if trying_to_shoot and time_since_last_shot >= current_rate:
		attempt_fire()

@rpc("call_local", "any_peer")
func equip_weapon(target_primary: bool):
	is_primary = target_primary
	
	if is_primary:
		secondary_gun.hide()
		primary_gun.show()
		muzzle = p_muzzle
	else:
		primary_gun.hide()
		secondary_gun.show()
		muzzle = s_muzzle
	
	# Only update UI if this is MY player
	if is_multiplayer_authority():
		update_ammo_ui()
		time_since_last_shot = 0.0 

func attempt_fire():
	var ammo_left = prim_ammo_current if is_primary else sec_ammo_current
	if ammo_left > 0:
		var dmg = prim_damage if is_primary else sec_damage
		shoot_raycast(dmg)
		
		# Play anim RPC so everyone sees you shoot
		rpc("play_shoot_anim_rpc") 
		
		# Recoil/Shake (Local Only)
		var kick = prim_recoil if is_primary else sec_recoil
		rotation_x += kick 
		current_shake = 0.05 if is_primary else 0.1 
		
		if is_primary: prim_ammo_current -= 1
		else: sec_ammo_current -= 1
		
		update_ammo_ui()
		time_since_last_shot = 0.0
	else:
		reload()

func reload():
	var current = prim_ammo_current if is_primary else sec_ammo_current
	var max_a = prim_ammo_max if is_primary else sec_ammo_max
	if current == max_a: return

	is_reloading = true
	ammo_label.text = "Reloading..."
	
	# Sync Reload Animation
	rpc("play_reload_anim_rpc")
	
	# We rely on the local timer/anim finish to refill ammo
	# (Animation length should match await time)
	await get_tree().create_timer(1.5).timeout
	
	if is_primary: prim_ammo_current = prim_ammo_max
	else: sec_ammo_current = sec_ammo_max
	is_reloading = false
	update_ammo_ui()

func update_ammo_ui():
	if not is_multiplayer_authority(): return
	var cur = prim_ammo_current if is_primary else sec_ammo_current
	var max_a = prim_ammo_max if is_primary else sec_ammo_max
	ammo_label.text = str(cur) + " / " + str(max_a)

# --- ANIMATION RPCS (So others see you shoot/reload) ---

@rpc("call_local", "any_peer")
func play_shoot_anim_rpc():
	if anim:
		if is_primary: anim.play("prim_shoot")
		else: anim.play("sec_shoot")
		anim.seek(0.0, true)

@rpc("call_local", "any_peer")
func play_reload_anim_rpc():
	if anim:
		if is_primary: anim.play("prim_reload")
		else: anim.play("sec_reload")

func shoot_raycast(dmg_amount):
	var vp = get_viewport().get_visible_rect().size * 0.5
	var cam_from = cam.project_ray_origin(vp)
	var cam_dir = cam.project_ray_normal(vp)
	var spread_amount = prim_spread if is_primary else sec_spread
	var spread_offset = (cam.global_transform.basis.x * randf_range(-spread_amount, spread_amount)) + \
						(cam.global_transform.basis.y * randf_range(-spread_amount, spread_amount))
	var final_dir = (cam_dir + spread_offset).normalized()
	var cam_to = cam_from + final_dir * max_aim_distance
	var hit = get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(cam_from, cam_to))
	var aim_target = hit.position if hit else cam_to
	var muzzle_pos = muzzle.global_position
	var bullet_dir = (aim_target - muzzle_pos).normalized()
	rpc("spawn_bullet", muzzle_pos, bullet_dir, dmg_amount, multiplayer.get_unique_id())

@rpc("call_local", "any_peer") 
func spawn_bullet(pos: Vector3, dir: Vector3, damage: int, shooter_id: int):
	var bullet = Bullet_Scene.instantiate()
	bullet.transform.origin = pos
	bullet.direction = dir
	if "damage" in bullet: bullet.damage = damage
	if "shooter_id" in bullet: bullet.shooter_id = shooter_id
	get_tree().root.add_child(bullet)

# ------------------------------------------------------------------
#  MOVEMENT, DAMAGE & FEEL (Standard Logic)
# ------------------------------------------------------------------

func check_interaction():
	if raycast.is_colliding():
		var hit = raycast.get_collider()
		if hit:
			if hit.is_in_group("vault"): hit.plant()
			elif hit.is_in_group("money"): hit.loot()
			elif hit.is_in_group("vaultdoor"): hit.owner.plant()
			elif hit.is_in_group("player"):
				if hit.state == PlayerState.DOWNED: hit.rpc("revive")

@rpc("any_peer", "call_local")
func receive_damage(amount):
	if state == PlayerState.SPECTATING: return
	current_health -= amount
	if health_bar: health_bar.value = current_health
	if mesh:
		var tween = create_tween()
		tween.tween_property(mesh, "scale", Vector3(1.1, 0.9, 1.1), 0.1)
		tween.tween_property(mesh, "scale", stand_scale, 0.1)
	if current_health <= 0:
		if state != PlayerState.DOWNED: go_downed()
		else: die() 

func go_downed():
	state = PlayerState.DOWNED
	current_health = downed_health 
	if health_bar: health_bar.value = current_health; health_bar.modulate = Color(1, 0, 0)
	name_label.text = name_label.text + " (Downed)"

@rpc("any_peer", "call_local")
func revive():
	state = PlayerState.IDLE
	current_health = 50 
	if health_bar: health_bar.value = current_health; health_bar.modulate = Color(1, 1, 1)
	update_player_name(NetworkManager.connected_players)

func die():
	state = PlayerState.SPECTATING
	hide() 
	$CollisionShape3D.disabled = true 
	if ui_layer: ui_layer.hide() # Hide UI on death
	check_all_dead()

func check_all_dead():
	var alive_count = 0
	var players = get_tree().get_nodes_in_group("player")
	for p in players:
		if p.state != PlayerState.SPECTATING: alive_count += 1
	if alive_count == 0: all_dead()

func all_dead():
	print("GAME OVER - ALL DEAD")
	
	# Only the Host triggers the game over sequence to avoid conflicts
	if multiplayer.is_server():
		# Call GameManager to end game. 
		# Passing 'false' tells the End Screen it was a FAILURE.
		GameManager.rpc("end_game", false)

func spectate_behavior():
	if Input.is_action_just_pressed("shoot"): switch_spectator_target()
	update_spectator_cam()

func switch_spectator_target():
	var players = get_tree().get_nodes_in_group("player")
	var alive_players = []
	for p in players:
		if p != self and p.state != PlayerState.SPECTATING: alive_players.append(p)
	if alive_players.size() > 0:
		spectate_target_idx = (spectate_target_idx + 1) % alive_players.size()

func update_spectator_cam():
	var players = get_tree().get_nodes_in_group("player")
	var alive_players = []
	for p in players:
		if p != self and p.state != PlayerState.SPECTATING: alive_players.append(p)
	if alive_players.size() > 0:
		if spectate_target_idx >= alive_players.size(): spectate_target_idx = 0
		var target = alive_players[spectate_target_idx]
		cam.global_position = cam.global_position.lerp(target.global_position + Vector3(0, 1.5, 0), 0.1)

func update_state() -> void:
	if state == PlayerState.DOWNED: return
	if not is_on_floor(): state = PlayerState.AIR; return
	if is_crouching: state = PlayerState.CROUCH; return
	var input_len = Input.get_vector("left", "right", "forward", "backward").length()
	if input_len > 0.1: state = PlayerState.RUN if Input.is_action_pressed("sprint") else PlayerState.WALK
	else: state = PlayerState.IDLE

func apply_state_effects(_delta: float) -> void:
	match state:
		PlayerState.IDLE: current_speed = walk_speed; bob_speed = 2.0; bob_amount = 0.01
		PlayerState.WALK: current_speed = walk_speed; bob_speed = 8.0; bob_amount = 0.04
		PlayerState.RUN: current_speed = sprint_speed; bob_speed = 12.0; bob_amount = 0.08
		PlayerState.CROUCH: current_speed = crouch_speed; bob_speed = 6.0; bob_amount = 0.03
		PlayerState.AIR: pass

func apply_movement(delta):
	var input = Input.get_vector("left", "right", "forward", "backward")
	var direction = (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_crouching: velocity.y = jump_height; floor_snap_length = 0.0 
	else: floor_snap_length = 0.3 
	var horizontal = Vector3(velocity.x, 0, velocity.z)
	if direction != Vector3.ZERO: horizontal = direction * current_speed
	else: horizontal = horizontal.move_toward(Vector3.ZERO, decel_speed * delta)
	velocity.x = horizontal.x; velocity.z = horizontal.z

func apply_crouch_scale(delta):
	var target_scale = stand_scale
	if state == PlayerState.CROUCH: target_scale = crouch_scale
	elif state == PlayerState.DOWNED: target_scale = downed_scale
	scale = scale.lerp(target_scale, delta * crouch_lerp_speed)

func apply_gravity(delta):
	if not is_on_floor(): velocity.y -= gravity * delta

func _unhandled_input(event):
	if not is_multiplayer_authority(): return
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity * 0.01)
		rotation_x -= event.relative.y * mouse_sensitivity * 0.01
		rotation_x = clamp(rotation_x, deg_to_rad(-60), deg_to_rad(15))
		pivot.rotation.x = rotation_x

func apply_head_bob(delta):
	if state == PlayerState.AIR:
		cam.position = cam.position.lerp(original_cam_pos, delta * 10); return
	var velocity_2d = Vector2(velocity.x, velocity.z).length()
	if velocity_2d < 0.1:
		cam.position = cam.position.lerp(original_cam_pos, delta * 10); return
	bob_time += delta * bob_speed
	cam.position = original_cam_pos + Vector3(0, sin(bob_time) * bob_amount, 0)

func apply_camera_shake_and_recoil(delta):
	current_shake = lerp(current_shake, 0.0, delta * shake_decay)
	var shake_offset = Vector3(randf_range(-current_shake, current_shake), randf_range(-current_shake, current_shake), 0)
	cam.rotation.z = shake_offset.z; cam.h_offset = shake_offset.x; cam.v_offset = shake_offset.y
	rotation_x = clamp(rotation_x, deg_to_rad(-80), deg_to_rad(60))
	pivot.rotation.x = rotation_x

func update_display(amount):
	money_label.text = "Team Take: $" + str(amount)
