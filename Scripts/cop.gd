extends CharacterBody3D

@onready var pivot = $pivot
@onready var primary_gun = $pivot/primary_gun
@onready var p_muzzle = $pivot/primary_gun/gun_muzzle

@onready var ray = $pivot/RayCast3D
@onready var ray_left = $pivot/RayLeft
@onready var ray_right = $pivot/RayRight

@export var Bullet_Scene: PackedScene
@export var speed := 5.0
@export var shoot_range := 12.0
@export var fov_angle := 180.0
@export var shoot_delay := 0.6

var target: Node3D = null
var active_ray = null
var can_shoot = true

var left_angle := 0.0
var left_dir := 1

var right_angle := 0.0
var right_dir := -1

var scan_speed := 60.0
var scanning := true


func _ready():
	primary_gun.show()
	make_cop_dress()


func _physics_process(delta):
	if scanning:
		_scan_left(delta)
		_scan_right(delta)

	_detect_player()

	if target:
		_rotate_to(target)
		var d = global_transform.origin.distance_to(target.global_transform.origin)
		if d < shoot_range:
			velocity = Vector3.ZERO
			if can_shoot:
				_shoot()
		else:
			var dir = target.global_transform.origin - global_transform.origin
			dir.y = 0
			velocity = dir.normalized() * speed
	else:
		velocity = Vector3.ZERO

	move_and_slide()


# LEFT SCAN: -90 → 0 → 90 → 0 → repeat
func _scan_left(delta):
	left_angle += left_dir * scan_speed * delta
	if left_angle >= 90.0:
		left_angle = 90.0
		left_dir = -1
	elif left_angle <= -90.0:
		left_angle = -90.0
		left_dir = 1
	ray_left.rotation = Vector3(0, deg_to_rad(left_angle), 0)


# RIGHT SCAN: 90 → 0 → -90 → 0 → repeat
func _scan_right(delta):
	right_angle += right_dir * scan_speed * delta
	if right_angle >= 90.0:
		right_angle = 90.0
		right_dir = -1
	elif right_angle <= -90.0:
		right_angle = -90.0
		right_dir = 1
	ray_right.rotation = Vector3(0, deg_to_rad(right_angle), 0)


# DETECTION SYSTEM (left / right / forward)
func _detect_player():
	var hit_forward = ray.is_colliding() and ray.get_collider().is_in_group("player")
	var hit_left = ray_left.is_colliding() and ray_left.get_collider().is_in_group("player")
	var hit_right = ray_right.is_colliding() and ray_right.get_collider().is_in_group("player")

	# FORWARD RAY DETECTS
	if hit_forward:
		var body = ray.get_collider()
		if _in_fov(body):
			target = body
			active_ray = ray
			scanning = false
			_point_other_ray_to_target(ray_left)
			_point_other_ray_to_target(ray_right)
			return

	# LEFT RAY DETECTS
	if hit_left:
		var body = ray_left.get_collider()
		if _in_fov(body):
			target = body
			active_ray = ray_left
			scanning = false
			_point_other_ray_to_target(ray_right)
			_point_other_ray_to_target(ray)
			return

	# RIGHT RAY DETECTS
	if hit_right:
		var body = ray_right.get_collider()
		if _in_fov(body):
			target = body
			active_ray = ray_right
			scanning = false
			_point_other_ray_to_target(ray_left)
			_point_other_ray_to_target(ray)
			return

	# Nothing detected → resume scanning
	target = null
	active_ray = null
	scanning = true


# Rotate inactive raycasts toward the detected player
func _point_other_ray_to_target(rc):
	var dir = target.global_transform.origin - rc.global_transform.origin
	dir.y = 0
	rc.look_at(rc.global_transform.origin + dir, Vector3.UP)


func _in_fov(body):
	var to_p = (body.global_transform.origin - global_transform.origin).normalized()
	var f = -global_transform.basis.z.normalized()
	var ang = rad_to_deg(acos(f.dot(to_p)))
	return ang <= fov_angle * 0.5


func _rotate_to(body):
	var p = body.global_transform.origin
	p.y = global_transform.origin.y
	look_at(p, Vector3.UP)


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
	_set_color(bean.get_node("Torus"), Color(0, 0, 0))


func _set_color(mesh, color):
	if mesh == null or mesh.mesh == null:
		return
	for i in range(mesh.mesh.get_surface_count()):
		var m = mesh.get_active_material(i)
		if m:
			var n = m.duplicate()
			n.albedo_color = color
			mesh.set_surface_override_material(i, n)
