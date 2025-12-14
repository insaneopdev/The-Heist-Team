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
@onready var bottom = $check/bottom
@onready var up = $check/up

# =========================
# EXPORTS
# =========================
@export var Bullet_Scene: PackedScene
@export var speed := 3.0
@export var shoot_range := 10.0
@export var fov_angle := 180.0
@export var shoot_delay := 0.8
@export var jump_height := 5.0
@export var gravity : float = 20.0

var health = 100

# =========================
# VARIABLES
# =========================
var target: Node3D = null
var can_shoot := true
var detected := false
var detected_source := ""

var left_angle := 0.0
var left_dir := 1
var right_angle := 0.0
var right_dir := -1

var scan_speed := 60.0
var scanning := true

var lose_delay := 0.5
var lose_timer := 0.0


# =========================
# READY
# =========================
func _ready():
	GameManager.register_enemy()
	secondary_gun.show()
	make_watchman_dress()


# =========================
# PHYSICS
# =========================
func _physics_process(delta):

	_detect_player(delta)

	if scanning and not detected:
		_scan_left(delta)
		_scan_right(delta)

	if detected and target:
		_reset_scan_rays()
		_rotate_to(target)

		var d = global_transform.origin.distance_to(target.global_transform.origin)
		if d < shoot_range:
			velocity.x = 0
			velocity.z = 0
			if can_shoot:
				_shoot()
		else:
			var dir = target.global_transform.origin - global_transform.origin
			dir.y = 0
			dir = dir.normalized()
			velocity.x = dir.x * speed
			velocity.z = dir.z * speed
	else:
		velocity.x = 0
		velocity.z = 0

	_apply_gravity(delta)
	move_and_slide()





# ============================================================
# DETECTION
# ============================================================
func _detect_player(delta):

	if detected_source == "area" and detected and target:
		return

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
# AREA SIGNALS
# ============================================================
func _on_area_3d_body_entered(body: Node3D):
	if not body.is_in_group("player"):
		return

	detected = true
	target = body
	detected_source = "area"
	scanning = false
	lose_timer = 0.0


func _on_area_3d_body_exited(body: Node3D):
	if not body.is_in_group("player"):
		return

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

	var b = Bullet_Scene.instantiate()
	b.global_transform = s_muzzle.global_transform
	b.direction = -pivot.global_transform.basis.z.normalized()
	get_tree().current_scene.add_child(b)

	await get_tree().create_timer(shoot_delay).timeout
	can_shoot = true


# ============================================================
# SCANNING
# ============================================================
func _scan_left(delta):
	left_angle += left_dir * scan_speed * delta
	if left_angle >= 90:
		left_angle = 90
		left_dir = -1
	elif left_angle <= -90:
		left_angle = -90
		left_dir = 1
	ray_left.rotation.y = deg_to_rad(left_angle)


func _scan_right(delta):
	right_angle += right_dir * scan_speed * delta
	if right_angle >= 90:
		right_angle = 90
		right_dir = -1
	elif right_angle <= -90:
		right_angle = -90
		right_dir = 1
	ray_right.rotation.y = deg_to_rad(right_angle)


# ============================================================
# GRAVITY
# ============================================================
func _apply_gravity(delta):
	if not is_on_floor():
		velocity.y -= gravity * delta


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

# MODIFIED: Now accepts attacker_id
# MODIFIED: Accepts attacker_id
@rpc("any_peer", "call_local")
func receive_damage(amount, attacker_id):
	health -= amount
	
	if health <= 0:
		die(attacker_id)

func die(killer_id):
	if multiplayer.is_server():
		GameManager.enemy_died()
		GameManager.add_kill(killer_id)
	remove_from_group("enemy")
	$CollisionShape3D.disabled = true
	queue_free()
