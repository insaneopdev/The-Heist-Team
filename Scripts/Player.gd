extends CharacterBody3D

#NODES RELATION
@onready var pivot = $pivot
@onready var mesh = $"."
@onready var primary_gun = $pivot/primary_gun
@onready var secondary_gun = $pivot/secondary_gun
@onready var p_muzzle = $pivot/primary_gun/gun_muzzle
@onready var s_muzzle = $pivot/secondary_gun/gun_muzzle
@onready var cam = $pivot/Camera3D   # CAMERA RELATION FOR AIM SYSTEM

#SCENE
@export var Bullet_Scene : PackedScene

# PLAYER VARIABLES 
@export var walk_speed = 5.0
@export var sprint_speed = 8.0
@export var jump_height = 10.0
@export var crouch_speed = 3.0

#SYSTEM VARIABLES
@export var mouse_sensitivity := 0.2
@export var max_aim_distance := 1000.0   # AIM RAYCAST RANGE

# ENVIRONMENT VARIABLES
@export var gravity = 20.0

#OTHER VARIABLES
var rotation_x := 0.0
var is_crouching = false
var crouch_scale = Vector3(1, 0.6, 1)
var normal_scale = Vector3(1, 1, 1)
var crouch_scale_speed = 10.0
var current_speed = 0.0
var is_primary = true
var muzzle = null

#STATE MACHINE
enum PlayerState { IDLE, WALK, RUN, CROUCH, AIR }
var state : PlayerState = PlayerState.IDLE


func _ready() -> void:
	primary_gun.show()
	secondary_gun.hide()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	muzzle = p_muzzle


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("crouch"):
		is_crouching = !is_crouching
	
	update_state()
	apply_state_effects(delta)
	gun_switch()
	shoot()
	apply_movement(delta)
	apply_gravity(delta)

	if is_crouching:
		mesh.scale = mesh.scale.lerp(crouch_scale, crouch_scale_speed * delta)
	else:
		mesh.scale = mesh.scale.lerp(normal_scale, crouch_scale_speed * delta)

	move_and_slide()


#STATE MACHINE 
func update_state() -> void:
	if not is_on_floor():
		state = PlayerState.AIR
		return
	
	if is_crouching:
		state = PlayerState.CROUCH
		return

	var input_vec = Input.get_vector("left", "right", "forward", "backward")
	var moving = input_vec.length() > 0.1

	if moving:
		if Input.is_action_pressed("sprint"):
			state = PlayerState.RUN
		else:
			state = PlayerState.WALK
	else:
		state = PlayerState.IDLE


#STATE EFFECTS  
func apply_state_effects(_delta: float) -> void:
	match state:
		PlayerState.IDLE:
			current_speed = walk_speed
		
		PlayerState.WALK:
			current_speed = walk_speed
		
		PlayerState.RUN:
			current_speed = sprint_speed
		
		PlayerState.CROUCH:
			current_speed = crouch_speed
		
		PlayerState.AIR:
			pass


# MOVEMENT 
func apply_movement(delta: float) -> void:
	var input = Input.get_vector("left", "right", "forward", "backward")
	var direction = (transform.basis * Vector3(input.x, 0, input.y)).normalized()

	var speed = current_speed

	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_crouching:
		velocity.y = jump_height

	var horizontal_velocity = velocity
	horizontal_velocity.y = 0

	if direction != Vector3.ZERO:
		horizontal_velocity = direction * speed
	else:
		horizontal_velocity = horizontal_velocity.move_toward(Vector3.ZERO, speed * delta)

	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z


# GUN SWITCH
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


# AIM POINT SYSTEM (SCREEN CENTER)
func get_aim_point():
	# GET SCREEN CENTER
	var screen_center = Vector2(
		get_viewport().get_visible_rect().size.x * 0.5,
		get_viewport().get_visible_rect().size.y * 0.5
	)

	# RAY ORIGIN + RAY DIRECTION FROM CAMERA
	var from = cam.project_ray_origin(screen_center)
	var dir = cam.project_ray_normal(screen_center)
	var to = from + dir * max_aim_distance

	# RAYCAST IN WORLD
	var space = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_bodies = true
	query.collide_with_areas = true

	var result = space.intersect_ray(query)

	if result:
		return result.position
	
	return to


# SHOOTING MECHANISM
func shoot():
	if Input.is_action_just_pressed("shoot"):
		var aim_point = get_aim_point()

		# ALIGN MUZZLE WITH AIM POINT
		muzzle.look_at(aim_point, Vector3.UP)

		var bullet = Bullet_Scene.instantiate()
		bullet.global_transform = muzzle.global_transform
		get_tree().current_scene.add_child(bullet)


#GRAVITY 
func apply_gravity(delta):
	if not is_on_floor():
		velocity.y -= gravity * delta


# MOUSE ROTATION
func _unhandled_input(event):
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity * 0.01)

		rotation_x -= event.relative.y * mouse_sensitivity * 0.01
		rotation_x = clamp(rotation_x, deg_to_rad(-75), deg_to_rad(75))

		pivot.rotation.x = rotation_x
