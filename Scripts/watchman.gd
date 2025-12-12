extends CharacterBody3D

# =========================
# NODE REFERENCES
# =========================
@onready var pivot = $pivot
@onready var secondary_gun = $pivot/secondary_gun
@onready var s_muzzle = $pivot/secondary_gun/gun_muzzle

@onready var ray = $pivot/RayCast3D
@onready var ray_left = $pivot/RayLeft
@onready var ray_right = $pivot/RayRight
@onready var area = $pivot/Area3D

# =========================
# EXPORTS
# =========================
@export var Bullet_Scene: PackedScene
@export var speed := 3.0
@export var shoot_range := 10.0
@export var fov_angle := 180.0
@export var shoot_delay := 0.8

# =========================
# VARIABLES
# =========================
var target: Node3D = null
var can_shoot = true
var detected: bool = false
var detected_source := ""  # forward / left / right / area

var left_angle := 0.0
var left_dir := 1
var right_angle := 0.0
var right_dir := -1

var scan_speed := 60.0
var scanning := true

# Delay before fully losing target
var lose_delay := 0.5
var lose_timer := 0.0


func _ready():
	secondary_gun.show()
	make_watchman_dress()


func _physics_process(delta):

	_detect_player(delta)

	if scanning and not detected:
		_scan_left(delta)
		_scan_right(delta)

	if detected and target:
		# Stop scanning rotation while tracking the target
		_reset_scan_rays()

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



# ============================================================
# DETECTION (RAY + AREA PRIORITY)
# ============================================================
func _detect_player(delta):

	# AREA ALWAYS OVERRIDES RAYCAST
	if detected_source == "area" and detected and target:
		return

	# Reset ray detection
	if detected_source != "area":
		detected = false
		target = null
		detected_source = ""
		scanning = true

	var hit_forward = ray.is_colliding() and ray.get_collider().is_in_group("player")
	var hit_left = ray_left.is_colliding() and ray_left.get_collider().is_in_group("player")
	var hit_right = ray_right.is_colliding() and ray_right.get_collider().is_in_group("player")

	if hit_forward:
		var body = ray.get_collider()
		if _in_fov(body):
			_set_detected(body, "forward")
			return

	if hit_left:
		var body = ray_left.get_collider()
		if _in_fov(body):
			_set_detected(body, "left")
			return

	if hit_right:
		var body = ray_right.get_collider()
		if _in_fov(body):
			_set_detected(body, "right")
			return

	# If previously detected but now rays see nothing → start countdown
	if not detected:
		lose_timer += delta
		if lose_timer >= lose_delay:
			target = null
			scanning = true
	else:
		lose_timer = 0.0



func _set_detected(body, src):
	detected = true
	target = body
	detected_source = src
	scanning = false
	lose_timer = 0.0



# ============================================================
# AREA3D SIGNALS
# ============================================================
func _on_area_3d_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return

	print("AREA DETECTED PLAYER")
	detected = true
	target = body
	detected_source = "area"
	scanning = false
	lose_timer = 0.0



func _on_area_3d_body_exited(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return

	print("AREA LOST PLAYER")

	# Start losing countdown
	detected_source = ""
	detected = false
	target = null
	scanning = true



# ============================================================
# HELPERS
# ============================================================
func _in_fov(body):
	var to_p = (body.global_transform.origin - global_transform.origin).normalized()
	var forward = -global_transform.basis.z.normalized()
	var ang = rad_to_deg(acos(forward.dot(to_p)))
	return ang <= fov_angle * 0.5


func _rotate_to(body):
	var p = body.global_transform.origin
	p.y = global_transform.origin.y
	look_at(p, Vector3.UP)


func _reset_scan_rays():
	ray_left.rotation = Vector3.ZERO
	ray_right.rotation = Vector3.ZERO



# ============================================================
# SHOOTING
# ============================================================
func _shoot():
	can_shoot = false
	print("SHOOT FROM:", detected_source)

	var b = Bullet_Scene.instantiate()
	b.global_transform = s_muzzle.global_transform
	b.direction = -pivot.global_transform.basis.z.normalized()
	get_tree().current_scene.add_child(b)

	await get_tree().create_timer(shoot_delay).timeout
	can_shoot = true



# ============================================================
# SCANNING SYSTEM
# ============================================================
func _scan_left(delta):
	left_angle += left_dir * scan_speed * delta
	if left_angle >= 90.0:
		left_angle = 90.0
		left_dir = -1
	elif left_angle <= -90.0:
		left_angle = -90.0
		left_dir = 1

	ray_left.rotation = Vector3(0, deg_to_rad(left_angle), 0)



func _scan_right(delta):
	right_angle += right_dir * scan_speed * delta
	if right_angle >= 90.0:
		right_angle = 90.0
		right_dir = -1
	elif right_angle <= -90.0:
		right_angle = -90.0
		right_dir = 1

	ray_right.rotation = Vector3(0, deg_to_rad(right_angle), 0)



# ============================================================
# COLORS
# ============================================================
func make_watchman_dress():
	var bean = $mesh/bean
	_set_color(bean.get_node("Sphere"), Color(0.4, 0.6, 1.0))
	_set_color(bean.get_node("Sphere_003"), Color(0.05, 0.05, 0.1))
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
