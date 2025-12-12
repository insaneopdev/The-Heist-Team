extends CharacterBody3D

# ==============================
# NODE REFERENCES
# ==============================
@onready var pivot           = $pivot
@onready var primary_gun     = $pivot/primary_gun
@onready var p_muzzle        = $pivot/primary_gun/gun_muzzle
@onready var ray_forward     = $pivot/RayCast3D
@onready var ray_left        = $pivot/RayLeft
@onready var ray_right       = $pivot/RayRight
@onready var vision_area     = $pivot/Area3D

# ==============================
# EXPORTS
# ==============================
@export var Bullet_Scene: PackedScene
@export var speed := 5.0
@export var shoot_range := 12.0
@export var fov_angle := 180.0
@export var shoot_delay := 0.6

# ==============================
# STATES
# ==============================
var detected: bool = false
var detection_source := ""        # "forward", "left", "right", "area"
var target: Node3D = null
var active_ray = null
var can_shoot := true
var scanning := true

# ==============================
# SCANNING
# ==============================
var left_angle := 0.0
var right_angle := 0.0
var scan_speed := 45.0
var left_dir := 1
var right_dir := -1

# ==============================
# LOST PLAYER SEARCH
# ==============================
var last_player_pos := Vector3.ZERO
var searching_lost_player := false
var search_timer := 0.0
var max_search_time := 2.0
var chase_speed_multiplier := 1.35
var search_arrival_dist := 1.0


# ==============================
# READY
# ==============================
func _ready():
	primary_gun.show()
	make_cop_dress()


# ==============================
# PHYSICS LOOP
# ==============================
func _physics_process(delta):

	_detect_player()

	# Show debug
	#print("DETECTED:", detected, " | SRC:", detection_source)

	# SCANNING
	if scanning and not searching_lost_player:
		_scan_left(delta)
		_scan_right(delta)

	# BEHAVIOR
	if detected and target:
		_do_detected_behavior(delta)

	elif searching_lost_player:
		_do_search_behavior(delta)

	else:
		velocity = Vector3.ZERO

	move_and_slide()


# ==============================
# WHEN PLAYER DETECTED
# ==============================
func _do_detected_behavior(delta):

	searching_lost_player = false
	search_timer = 0.0

	last_player_pos = target.global_transform.origin
	_rotate_to(target)

	var dist = global_transform.origin.distance_to(target.global_transform.origin)

	# Shoot range
	if dist <= shoot_range:
		velocity = Vector3.ZERO
		if can_shoot:
			_shoot()

	# Chase movement
	else:
		var dir = (target.global_transform.origin - global_transform.origin)
		dir.y = 0
		velocity = dir.normalized() * speed


# ==============================
# SEARCH LAST KNOWN LOCATION
# ==============================
func _do_search_behavior(delta):

	search_timer += delta

	var dir = last_player_pos - global_transform.origin
	dir.y = 0

	# If reached last known spot → scan there
	if dir.length() < search_arrival_dist:
		velocity = Vector3.ZERO
		_scan_left(delta)
		_scan_right(delta)

		if search_timer >= max_search_time:
			searching_lost_player = false
			scanning = true
		return

	# Move toward last known player
	velocity = dir.normalized() * speed * chase_speed_multiplier


# ==============================
# SCANNING SYSTEM
# ==============================
func _scan_left(delta):
	left_angle += left_dir * scan_speed * delta
	if left_angle > 90: left_angle = 90; left_dir = -1
	if left_angle < -90: left_angle = -90; left_dir = 1
	ray_left.rotation.y = deg_to_rad(left_angle)

func _scan_right(delta):
	right_angle += right_dir * scan_speed * delta
	if right_angle > 90: right_angle = 90; right_dir = -1
	if right_angle < -90: right_angle = -90; right_dir = 1
	ray_right.rotation.y = deg_to_rad(right_angle)


# ==============================
# DETECTION SYSTEM
# ==============================
func _detect_player():

	var area_prior = (detection_source == "area")

	# If Area3D already sees player → DO NOT RESET DETECTION
	if area_prior:
		detected = true
		return

	# Otherwise raycast detection controls the state
	var f = ray_forward.is_colliding() and ray_forward.get_collider().is_in_group("player")
	var l = ray_left.is_colliding() and ray_left.get_collider().is_in_group("player")
	var r = ray_right.is_colliding() and ray_right.get_collider().is_in_group("player")

	# FORWARD
	if f:
		_set_detected(ray_forward, ray_forward.get_collider(), "forward")
		return

	# LEFT
	if l:
		_set_detected(ray_left, ray_left.get_collider(), "left")
		return

	# RIGHT
	if r:
		_set_detected(ray_right, ray_right.get_collider(), "right")
		return

	# LOST → Enter searching mode
	if detected:
		searching_lost_player = true
		search_timer = 0.0
		scanning = false

	detected = false
	detection_source = ""
	target = null
	active_ray = null


# ==============================
# TARGET ACQUIRED
# ==============================
func _set_detected(rc, body, src):

	target = body
	active_ray = rc
	detected = true
	detection_source = src

	scanning = false
	searching_lost_player = false
	search_timer = 0.0

	_point_ray(ray_forward)
	_point_ray(ray_left)
	_point_ray(ray_right)


# ==============================
# AREA3D DETECTION
# ==============================
func _on_area_3d_body_entered(body):
	if not body.is_in_group("player"):
		return

	print("AREA DETECTED PLAYER!")

	detected = true
	detection_source = "area"
	target = body
	last_player_pos = body.global_transform.origin

	scanning = false
	searching_lost_player = false
	search_timer = 0.0

	_point_ray(ray_forward)
	_point_ray(ray_left)
	_point_ray(ray_right)


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
func _point_ray(rc):
	if target == null: return
	var dir = target.global_transform.origin - rc.global_transform.origin
	dir.y = 0
	if dir.length() > 0.01:
		rc.look_at(rc.global_transform.origin + dir, Vector3.UP)


func _rotate_to(body):
	var pos = body.global_transform.origin
	pos.y = global_transform.origin.y
	look_at(pos, Vector3.UP)


# ==============================
# SHOOT
# ==============================
func _shoot():
	can_shoot = false

	print("SHOOTING FROM:", detection_source)

	var b = Bullet_Scene.instantiate()
	b.global_transform = p_muzzle.global_transform
	b.direction = -pivot.global_transform.basis.z.normalized()

	get_tree().current_scene.add_child(b)

	await get_tree().create_timer(shoot_delay).timeout
	can_shoot = true


# ==============================
# MATERIAL COLOR
# ==============================
func make_cop_dress():
	var bean = $mesh/bean
	_set_color(bean.get_node("Sphere"), Color(0.0, 0.1, 0.3))
	_set_color(bean.get_node("Sphere_003"), Color(0.0, 0.1, 0.3))
	_set_color(bean.get_node("Torus"), Color.BLACK)


func _set_color(mesh, color):
	if mesh == null or mesh.mesh == null:
		return
	for i in mesh.mesh.get_surface_count():
		var m = mesh.get_active_material(i)
		if m:
			var nm = m.duplicate()
			nm.albedo_color = color
			mesh.set_surface_override_material(i, nm)
