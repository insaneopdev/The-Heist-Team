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
@onready var money_label = $CanvasLayer/MoneyLabel
@onready var name_label = $NameLabel
@onready var ammo_label = $CanvasLayer/AmmoLabel
@onready var anim = $AnimationPlayer 

# --- SCENE ---
@export var Bullet_Scene : PackedScene

# --- MOVEMENT VARIABLES ---
@export var walk_speed = 4.0
@export var sprint_speed = 6.0
@export var jump_height = 5.0
@export var crouch_speed = 3.0
var decel_speed := 12.0  
@export var mouse_sensitivity := 0.2
@export var max_aim_distance := 1000.0
@export var gravity : float = 20.0

# --- WEAPON SETTINGS ---
# Primary (Automatic)
var prim_ammo_max = 30
var prim_ammo_current = 30
var prim_fire_rate = 0.2
var prim_spread = 0.03
var prim_recoil = 0.03 

# Secondary (Semi-Auto)
var sec_ammo_max = 6
var sec_ammo_current = 6
var sec_fire_rate = 0.25 
var sec_spread = 0.01 
var sec_recoil = 0.05 

# Weapon State
var is_primary = true
var is_reloading = false
var time_since_last_shot = 0.0
var muzzle = null

# --- RECOIL & SHAKE VARIABLES ---
var current_shake = 0.0
var shake_decay = 10.0 
var rotation_x := 0.0

# --- OTHER VARIABLES ---
var is_crouching = false
var current_speed = 0.0

# Crouch Scaling
var stand_scale := Vector3(1, 1, 1)
var crouch_scale := Vector3(1, 0.8, 1)
var crouch_lerp_speed := 10.0

# Head Bob
var bob_time := 0.0
var bob_amount := 0.1         
var bob_speed := 10.0            
var original_cam_pos = null

enum PlayerState { IDLE, WALK, RUN, CROUCH, AIR }
var state : PlayerState = PlayerState.IDLE

# --- MULTIPLAYER SETUP ---
func _enter_tree():
	set_multiplayer_authority(str(name).to_int())

func _ready() -> void:
# FIX 1: Allow climbing steeper slopes (default is 45 degrees, we set to 50)
	floor_max_angle = deg_to_rad(50)
	
	# FIX 2: Set how far the player snaps to the floor (0.3 meters)
	# This keeps you grounded when walking down ramps
	floor_snap_length = 0.3

	money_label.text = "Team Take: $0"
	GameManager.money_updated.connect(update_display)

	NetworkManager.player_list_updated.connect(update_player_name)
	update_player_name(NetworkManager.connected_players)

	# --- REMOTE PLAYER ---
	if not is_multiplayer_authority():
		cam.current = false
		set_process_unhandled_input(false)
		if mesh: mesh.show()
		name_label.show()
		return

	# --- LOCAL PLAYER ---
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if mesh: mesh.hide()
	name_label.hide()
	
	raycast.add_exception(self)
	cam.position.z = 0.2 
	original_cam_pos = cam.position

	# Init Weapons
	muzzle = p_muzzle
	primary_gun.show()
	secondary_gun.hide()
	update_ammo_ui()

func update_player_name(players_dict):
	var my_id = str(name).to_int()
	var lookup_id = my_id
	if my_id == 1: lookup_id = NetworkManager.host_signaling_id
	
	if players_dict.has(lookup_id):
		name_label.text = players_dict[lookup_id]
	else:
		name_label.text = "Player " + str(lookup_id)

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority(): return

	time_since_last_shot += delta
	
	if not is_reloading:
		weapon_input_logic()
		
		if Input.is_action_just_pressed("crouch"): is_crouching = !is_crouching
		
		if Input.is_action_just_pressed("plant"):
			if raycast.is_colliding():
				var hit = raycast.get_collider()
				if hit:
					if hit.is_in_group("vault"): hit.plant()
					elif hit.is_in_group("money"): hit.loot()
					elif hit.is_in_group("vaultdoor"): hit.owner.plant()

	update_state()
	apply_state_effects(delta)
	apply_movement(delta)
	apply_gravity(delta)
	apply_head_bob(delta)
	
	# Apply Shake ON TOP of head bob
	apply_camera_shake_and_recoil(delta)
	
	apply_crouch_scale(delta)
	move_and_slide()

# ------------------------------------------------------------------
# WEAPON & FEEL SYSTEM
# ------------------------------------------------------------------

func weapon_input_logic():
	if Input.is_action_just_pressed("switch"):
		swap_weapons()
		return

	if Input.is_action_just_pressed("reload"):
		reload()
		return

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

func attempt_fire():
	var ammo_left = prim_ammo_current if is_primary else sec_ammo_current
	
	if ammo_left > 0:
		shoot_raycast()
		play_shoot_anim()
		
		# --- RECOIL & SHAKE ---
		var kick = prim_recoil if is_primary else sec_recoil
		rotation_x += kick 
		current_shake = 0.05 if is_primary else 0.1 
		
		# --- AMMO LOGIC ---
		if is_primary: prim_ammo_current -= 1
		else: sec_ammo_current -= 1
		
		update_ammo_ui()
		time_since_last_shot = 0.0
	else:
		reload()

func apply_camera_shake_and_recoil(delta):
	# Decay Shake
	current_shake = lerp(current_shake, 0.0, delta * shake_decay)
	
	# Apply Noise
	var shake_offset = Vector3(
		randf_range(-current_shake, current_shake),
		randf_range(-current_shake, current_shake),
		0
	)
	
	# Add to existing camera transforms (from Head Bob)
	cam.rotation.z = shake_offset.z 
	cam.h_offset = shake_offset.x
	cam.v_offset = shake_offset.y
	
	# Clamp Recoil
	rotation_x = clamp(rotation_x, deg_to_rad(-80), deg_to_rad(60))
	pivot.rotation.x = rotation_x

func shoot_raycast():
	var vp = get_viewport().get_visible_rect().size * 0.5
	var cam_from = cam.project_ray_origin(vp)
	var cam_dir = cam.project_ray_normal(vp)
	
	# --- SPREAD ---
	var spread_amount = prim_spread if is_primary else sec_spread
	var spread_offset = (cam.global_transform.basis.x * randf_range(-spread_amount, spread_amount)) + \
						(cam.global_transform.basis.y * randf_range(-spread_amount, spread_amount))
	
	var final_dir = (cam_dir + spread_offset).normalized()
	var cam_to = cam_from + final_dir * max_aim_distance
	
	var hit = get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(cam_from, cam_to)
	)

	var aim_target = hit.position if hit else cam_to
	var muzzle_pos = muzzle.global_position
	var bullet_dir = (aim_target - muzzle_pos).normalized()

	rpc("spawn_bullet", muzzle_pos, bullet_dir)

@rpc("call_local", "any_peer") 
func spawn_bullet(pos: Vector3, dir: Vector3):
	var bullet = Bullet_Scene.instantiate()
	bullet.transform.origin = pos
	bullet.direction = dir
	get_tree().root.add_child(bullet)

func reload():
	# 1. Check if ammo is already full (Don't reload if 30/30)
	var current = prim_ammo_current if is_primary else sec_ammo_current
	var max_a = prim_ammo_max if is_primary else sec_ammo_max
	if current == max_a: return

	# 2. Set State
	is_reloading = true
	ammo_label.text = "Reloading..."
	
	# 3. Play Animation & Wait
	if anim:
		# Play the correct animation based on weapon
		if is_primary:
			anim.play("prim_reload")
		else:
			anim.play("sec_reload")
		
		# WAITS here until the animation is fully done playing
		await anim.animation_finished
	else:
		# Fallback: If no AnimationPlayer found, just wait 1.5 seconds
		await get_tree().create_timer(1.5).timeout
	
	# 4. Refill Ammo (Only happens after animation finishes)
	if is_primary:
		prim_ammo_current = prim_ammo_max
	else:
		sec_ammo_current = sec_ammo_max
	
	# 5. Reset State
	is_reloading = false
	update_ammo_ui()

func swap_weapons():
	is_primary = !is_primary
	if is_primary:
		secondary_gun.hide(); primary_gun.show(); muzzle = p_muzzle
	else:
		primary_gun.hide(); secondary_gun.show(); muzzle = s_muzzle
	update_ammo_ui()
	time_since_last_shot = 0.0 

func update_ammo_ui():
	var cur = prim_ammo_current if is_primary else sec_ammo_current
	var max_a = prim_ammo_max if is_primary else sec_ammo_max
	ammo_label.text = str(cur) + " / " + str(max_a)

func play_shoot_anim():
	if anim:
		if is_primary: anim.play("prim_shoot")
		else: anim.play("sec_shoot")
		anim.seek(0.0, true) 

# ------------------------------------------------------------------
# MOVEMENT & SYSTEM FUNCTIONS
# ------------------------------------------------------------------

func update_state() -> void:
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
	
	# JUMP LOGIC UPDATED
	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_crouching:
		velocity.y = jump_height
		# CRITICAL: Turn off snapping when jumping, or the floor will pull you back down!
		floor_snap_length = 0.0 
	else:
		# Turn snapping back on when we are just walking
		floor_snap_length = 0.3

	var horizontal = Vector3(velocity.x, 0, velocity.z)
	
	if direction != Vector3.ZERO:
		horizontal = direction * current_speed
	else:
		horizontal = horizontal.move_toward(Vector3.ZERO, decel_speed * delta)
	
	velocity.x = horizontal.x
	velocity.z = horizontal.z

func apply_crouch_scale(delta):
	var target_scale = crouch_scale if is_crouching else stand_scale
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
		cam.position = cam.position.lerp(original_cam_pos, delta * 10)
		return
	var velocity_2d = Vector2(velocity.x, velocity.z).length()
	if velocity_2d < 0.1:
		cam.position = cam.position.lerp(original_cam_pos, delta * 10)
		return
	bob_time += delta * bob_speed
	cam.position = original_cam_pos + Vector3(0, sin(bob_time) * bob_amount, 0)

func update_display(amount):
	money_label.text = "Team Take: $" + str(amount)
