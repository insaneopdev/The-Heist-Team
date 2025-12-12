extends CharacterBody3D

# --- NODES RELATION ---
@onready var pivot = $pivot
@onready var mesh = $"." 
@onready var primary_gun = $pivot/primary_gun
@onready var secondary_gun = $pivot/secondary_gun
@onready var p_muzzle = $pivot/primary_gun/gun_muzzle
@onready var s_muzzle = $pivot/secondary_gun/gun_muzzle
@onready var cam = $pivot/Camera3D
@onready var raycast = $pivot/RayCast3D
@onready var money = $CanvasLayer/MoneyLabel

# --- SCENE ---
@export var Bullet_Scene : PackedScene

# --- PLAYER VARIABLES ---
@export var walk_speed = 4.0
@export var sprint_speed = 6.0
@export var jump_height = 5.0
@export var crouch_speed = 3.0
var decel_speed := 12.0  


# --- SYSTEM VARIABLES ---
@export var mouse_sensitivity := 0.2
@export var max_aim_distance := 1000.0

# --- ENVIRONMENT VARIABLES ---
@export var gravity : float = 20.0

# --- OTHER VARIABLES ---
var rotation_x := 0.0
var is_crouching = false
var current_speed = 0.0
var is_primary = true
var muzzle = null

# --- NEW CROUCH SYSTEM (SCALING PLAYER) ---
var stand_scale := Vector3(1, 1, 1)
var crouch_scale := Vector3(1, 0.6, 1)
var crouch_lerp_speed := 10.0

# --- HEAD BOB VARIABLES ---
var bob_time := 0.0
var bob_amount := 0.1         
var bob_speed := 10.0            
var original_cam_pos = null

# --- STATE MACHINE ---
enum PlayerState { IDLE, WALK, RUN, CROUCH, AIR }
var state : PlayerState = PlayerState.IDLE

# --- MULTIPLAYER SETUP ---
func _enter_tree():
	set_multiplayer_authority(str(name).to_int())

func _ready() -> void:
	
	money.text = str("Team Take: $0")
	GameManager.money_updated.connect(update_display)

	if not is_multiplayer_authority():
		cam.current = false
		set_process_unhandled_input(false)
		return

	primary_gun.show()
	secondary_gun.hide()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	muzzle = p_muzzle

	original_cam_pos = cam.position


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	if Input.is_action_just_pressed("crouch"):
		is_crouching = !is_crouching

	if Input.is_action_just_pressed("plant"):
		if raycast.is_colliding():
			if raycast.get_collider().is_in_group("vault"):
				raycast.get_collider().plant()
			if raycast.get_collider().is_in_group("money"):
				raycast.get_collider().loot()
			if raycast.get_collider().is_in_group("vaultdoor"):
				raycast.get_collider().owner.plant()

	update_state()
	apply_state_effects(delta)
	gun_switch()
	shoot()
	apply_movement(delta)
	apply_gravity(delta)
	apply_head_bob(delta)
	apply_crouch_scale(delta)

	move_and_slide()


# --- STATE MACHINE ---
func update_state() -> void:
	if not is_on_floor():
		state = PlayerState.AIR
		return
	
	if is_crouching:
		state = PlayerState.CROUCH
		return

	var input_len = Input.get_vector("left", "right", "forward", "backward").length()

	if input_len > 0.1:
		if Input.is_action_pressed("sprint"):
			state = PlayerState.RUN
		else:
			state = PlayerState.WALK
	else:
		state = PlayerState.IDLE


# --- STATE EFFECTS ---
func apply_state_effects(_delta: float) -> void:
	match state:
		PlayerState.IDLE, PlayerState.WALK:
			current_speed = walk_speed
		PlayerState.RUN:
			current_speed = sprint_speed
		PlayerState.CROUCH:
			current_speed = crouch_speed
		PlayerState.AIR:
			pass


# --- MOVEMENT ---
func apply_movement(delta):

	var input = Input.get_vector("left", "right", "forward", "backward")
	var direction = (transform.basis * Vector3(input.x, 0, input.y)).normalized()

	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_crouching:
		velocity.y = jump_height

	var horizontal = Vector3(velocity.x, 0, velocity.z)

	if direction != Vector3.ZERO:
		horizontal = direction * current_speed
	else:
		# faster stop (less sliding)
		horizontal = horizontal.move_toward(Vector3.ZERO, decel_speed * delta)

	velocity.x = horizontal.x
	velocity.z = horizontal.z

# ------------------------------------------------------
# NEW CROUCH SYSTEM (SMOOTH SCALING)
# ------------------------------------------------------
func apply_crouch_scale(delta):
	var target_scale : Vector3

	if is_crouching:
		target_scale = crouch_scale
	else:
		target_scale = stand_scale

	scale = scale.lerp(target_scale, delta * crouch_lerp_speed)


# --- GUN SWITCH ---
func gun_switch():
	if Input.is_action_just_pressed("switch"):
		is_primary = !is_primary
		
		if is_primary:
			secondary_gun.hide()
			primary_gun.show()
			muzzle = p_muzzle
		else:
			primary_gun.hide()
			secondary_gun.show()
			muzzle = s_muzzle


# --- SHOOTING (MULTIPLAYER) ---
func shoot():
	if not Input.is_action_just_pressed("shoot"):
		return

	var vp = get_viewport().get_visible_rect().size * 0.5
	var cam_from = cam.project_ray_origin(vp)
	var cam_dir = cam.project_ray_normal(vp)
	var cam_to = cam_from + cam_dir * max_aim_distance
	
	var hit = get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(cam_from, cam_to)
	)

	var aim_target : Vector3
	if hit:
		aim_target = hit.position
	else:
		aim_target = cam_to

	var muzzle_pos = muzzle.global_position
	var bullet_dir = (aim_target - muzzle_pos).normalized()

	rpc("spawn_bullet", muzzle_pos, bullet_dir)


@rpc("call_local", "any_peer") 
func spawn_bullet(pos: Vector3, dir: Vector3):
	var bullet = Bullet_Scene.instantiate()
	bullet.transform.origin = pos
	bullet.direction = dir
	get_tree().root.add_child(bullet)


# --- GRAVITY ---
func apply_gravity(delta):
	if not is_on_floor():
		velocity.y -= gravity * delta


# --- MOUSE ROTATION ---
# --- MOUSE ROTATION ---
func _unhandled_input(event):
	if event is InputEventMouseMotion:
		
		# Horizontal rotation (player body)
		rotate_y(-event.relative.x * mouse_sensitivity * 0.01)

		# Vertical (camera + gun pivot)
		rotation_x -= event.relative.y * mouse_sensitivity * 0.01

		# LIMITS:
		# Up = -60 degrees
		# Down = +45 degrees
		var upper_limit = deg_to_rad(-60)
		var lower_limit = deg_to_rad(45)

		rotation_x = clamp(rotation_x, upper_limit, lower_limit)

		# Apply to pivot (gun + camera)
		pivot.rotation.x = rotation_x


# --- HEAD BOB ---
func apply_head_bob(delta):
	if state == PlayerState.AIR:
		cam.position = cam.position.lerp(original_cam_pos, delta * 10)
		return

	var velocity_2d = Vector2(velocity.x, velocity.z).length()

	match state:
		PlayerState.IDLE:
			bob_speed = 2
			bob_amount = 0.015
		PlayerState.WALK:
			bob_speed = 6
			bob_amount = 0.035
		PlayerState.RUN:
			bob_speed = 10
			bob_amount = 0.06
		PlayerState.CROUCH:
			bob_speed = 4
			bob_amount = 0.02

	if velocity_2d < 0.1:
		cam.position = cam.position.lerp(original_cam_pos, delta * 10)
		return

	bob_time += delta * bob_speed

	var bob_offset = Vector3(
		0,
		sin(bob_time) * bob_amount,
		0
	)

	cam.position = original_cam_pos + bob_offset


func update_display(amount):
	money.text = "TEAM CASH: $" + str(amount)
