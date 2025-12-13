extends CharacterBody3D

@onready var pivot           = $pivot
@onready var primary_gun     = $pivot/primary_gun
@onready var p_muzzle        = $pivot/primary_gun/gun_muzzle
@onready var ray_forward     = $pivot/RayCast3D
@onready var ray_left        = $pivot/RayLeft
@onready var ray_right       = $pivot/RayRight
@onready var vision_area     = $pivot/Area3D
@onready var nav_agent       = $NavigationAgent3D

@export var Bullet_Scene: PackedScene
@export var speed := 5.0
@export var shoot_range := 12.0
@export var shoot_delay := 0.6
@export var gravity := 20.0

var detected := false
var detection_source := ""
var target: Node3D = null
var can_shoot := true
var scanning := true

var left_angle := 0.0
var right_angle := 0.0
var scan_speed := 45.0
var left_dir := 1
var right_dir := -1

var last_player_pos := Vector3.ZERO
var searching_lost_player := false
var search_timer := 0.0
var max_search_time := 2.0
var chase_speed_multiplier := 1.35
var search_arrival_dist := 1.0

func _ready():
	await get_tree().process_frame
	primary_gun.show()
	make_cop_dress()

func _physics_process(delta):

	_detect_player()

	if scanning and not searching_lost_player:
		_scan_left(delta)
		_scan_right(delta)

	if detected and target:
		_do_detected_behavior(delta)

	elif searching_lost_player:
		_do_search_behavior(delta)

	else:
		velocity.x = 0
		velocity.z = 0

	if not is_on_floor():
		velocity.y -= gravity * delta

	move_and_slide()

# ==============================
# DETECTED BEHAVIOR
# ==============================
func _do_detected_behavior(delta):

	searching_lost_player = false
	search_timer = 0.0

	last_player_pos = target.global_position
	_rotate_to(target)

	var dist = global_position.distance_to(target.global_position)

	if dist <= shoot_range:
		velocity.x = 0
		velocity.z = 0
		if can_shoot:
			_shoot()
		return

	nav_agent.target_position = target.global_position
	_move_with_nav(speed)

# ==============================
# SEARCH LAST POSITION
# ==============================
func _do_search_behavior(delta):

	search_timer += delta

	nav_agent.target_position = last_player_pos
	_move_with_nav(speed * chase_speed_multiplier)

	if global_position.distance_to(last_player_pos) < search_arrival_dist:
		velocity.x = 0
		velocity.z = 0
		_scan_left(delta)
		_scan_right(delta)

		if search_timer >= max_search_time:
			searching_lost_player = false
			scanning = true

# ==============================
# NAV MOVEMENT (SMOOTH)
# ==============================
func _move_with_nav(move_speed):

	if nav_agent.is_navigation_finished():
		velocity.x = 0
		velocity.z = 0
		return

	var next_pos = nav_agent.get_next_path_position()
	var dir = next_pos - global_position
	dir.y = 0

	if dir.length() > 0.05:
		dir = dir.normalized()
		velocity.x = dir.x * move_speed
		velocity.z = dir.z * move_speed

# ==============================
# SCANNING
# ==============================
func _scan_left(delta):
	left_angle += left_dir * scan_speed * delta
	if left_angle > 90:
		left_angle = 90
		left_dir = -1
	elif left_angle < -90:
		left_angle = -90
		left_dir = 1
	ray_left.rotation.y = deg_to_rad(left_angle)

func _scan_right(delta):
	right_angle += right_dir * scan_speed * delta
	if right_angle > 90:
		right_angle = 90
		right_dir = -1
	elif right_angle < -90:
		right_angle = -90
		right_dir = 1
	ray_right.rotation.y = deg_to_rad(right_angle)

# ==============================
# DETECTION
# ==============================
func _detect_player():

	if detection_source == "area" and detected:
		return

	if ray_forward.is_colliding() and ray_forward.get_collider().is_in_group("player"):
		_set_detected(ray_forward.get_collider(), "forward")
		return

	if ray_left.is_colliding() and ray_left.get_collider().is_in_group("player"):
		_set_detected(ray_left.get_collider(), "left")
		return

	if ray_right.is_colliding() and ray_right.get_collider().is_in_group("player"):
		_set_detected(ray_right.get_collider(), "right")
		return

	if detected:
		searching_lost_player = true
		search_timer = 0.0
		scanning = false

	detected = false
	detection_source = ""
	target = null

func _set_detected(body, src):
	target = body
	detected = true
	detection_source = src
	scanning = false
	searching_lost_player = false
	search_timer = 0.0

# ==============================
# AREA
# ==============================
func _on_area_3d_body_entered(body):
	if body.is_in_group("player"):
		detected = true
		target = body
		detection_source = "area"
		last_player_pos = body.global_position
		scanning = false
		searching_lost_player = false
		search_timer = 0.0

func _on_area_3d_body_exited(body):
	if body.is_in_group("player"):
		detected = false
		detection_source = ""
		target = null
		searching_lost_player = true
		search_timer = 0.0

# ==============================
# HELPERS
# ==============================
func _rotate_to(body):
	var pos = body.global_position
	pos.y = global_position.y
	look_at(pos, Vector3.UP)

func _shoot():
	can_shoot = false
	var b = Bullet_Scene.instantiate()
	b.global_transform = p_muzzle.global_transform
	b.direction = -pivot.global_transform.basis.z.normalized()
	get_tree().current_scene.add_child(b)
	await get_tree().create_timer(shoot_delay).timeout
	can_shoot = true

func make_cop_dress():
	var bean = $mesh/bean
	_set_color(bean.get_node("Sphere"), Color(0.0, 0.1, 0.3))
	_set_color(bean.get_node("Sphere_003"), Color(0.0, 0.1, 0.3))
	_set_color(bean.get_node("Torus"), Color.BLACK)

func _set_color(mesh, color):
	for i in range(mesh.mesh.get_surface_count()):
		var m = mesh.get_active_material(i)
		if m:
			var n = m.duplicate()
			n.albedo_color = color
			mesh.set_surface_override_material(i, n)
