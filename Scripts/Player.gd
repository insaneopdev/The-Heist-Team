extends CharacterBody3D

#NODES RELATION
@onready var pivot = $pivot
@onready var mesh = $"."
@onready var primary_gun = $pivot/primary_gun
@onready var secondary_gun = $pivot/secondary_gun
@onready var p_muzzle = $pivot/primary_gun/gun_muzzle
@onready var s_muzzle = $pivot/secondary_gun/gun_muzzle
@onready var cam = $pivot/Camera3D

#SCENE
@export var Bullet_Scene : PackedScene

# PLAYER VARIABLES 
@export var walk_speed = 5.0
@export var sprint_speed = 8.0
@export var jump_height = 10.0
@export var crouch_speed = 3.0

#SYSTEM VARIABLES
@export var mouse_sensitivity := 0.2
@export var max_aim_distance := 1000.0

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

# HEAD BOB VARIABLES
var bob_time := 0.0
var bob_amount := 0.1         
var bob_speed := 10.0           
var original_cam_pos = null

#STATE MACHINE
enum PlayerState { IDLE, WALK, RUN, CROUCH, AIR }
var state : PlayerState = PlayerState.IDLE


func _ready() -> void:
	primary_gun.show()
	secondary_gun.hide()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	muzzle = p_muzzle
	original_cam_pos = cam.position


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("crouch"):
		is_crouching = !is_crouching

	update_state()
	apply_state_effects(delta)
	gun_switch()
	shoot()
	apply_movement(delta)
	apply_gravity(delta)
	apply_head_bob(delta)

	var target_scale = crouch_scale if is_crouching else normal_scale
	mesh.scale = mesh.scale.lerp(target_scale, crouch_scale_speed * delta)

	move_and_slide()


#STATE MACHINE 
func update_state() -> void:
	if not is_on_floor():
		state = PlayerState.AIR
		return
	
	if is_crouching:
		state = PlayerState.CROUCH
		return

	var input_len = Input.get_vector("left", "right", "forward", "backward").length()

	if input_len > 0.1:
		state = PlayerState.RUN if Input.is_action_pressed("sprint") else PlayerState.WALK
	else:
		state = PlayerState.IDLE


#STATE EFFECTS  
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


# MOVEMENT 
func apply_movement(delta: float) -> void:
	var input = Input.get_vector("left", "right", "forward", "backward")
	var direction = (transform.basis * Vector3(input.x, 0, input.y)).normalized()

	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_crouching:
		velocity.y = jump_height

	var horizontal = velocity
	horizontal.y = 0

	horizontal = direction * current_speed if direction != Vector3.ZERO else horizontal.move_toward(Vector3.ZERO, current_speed * delta)

	velocity.x = horizontal.x
	velocity.z = horizontal.z


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
	var vp = get_viewport().get_visible_rect().size * 0.5

	var from = cam.project_ray_origin(vp)
	var dir = cam.project_ray_normal(vp)
	var to = from + dir * max_aim_distance

	var result = get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, to)
	)

	return result.position if result else to


# SHOOTING MECHANISM
func shoot():
	if Input.is_action_just_pressed("shoot"):
		var aim_point = get_aim_point()

		var muzzle_pos = muzzle.get_global_position()
		var dir = (aim_point - muzzle_pos).normalized()

		var bullet = Bullet_Scene.instantiate()
		bullet.direction = dir
		bullet.transform.origin = muzzle_pos

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

		var gun_rot_x = clamp(rotation_x, deg_to_rad(-35), deg_to_rad(75))

		pivot.rotation.x = gun_rot_x
		
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
