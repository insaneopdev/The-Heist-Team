extends CharacterBody3D

# ==============================
# NODE REFERENCES
# ==============================
@onready var pivot       = $pivot
@onready var primary_gun = $pivot/primary_gun
@onready var p_muzzle    = $pivot/primary_gun/gun_muzzle
@onready var vision_area = $pivot/Area3D
@onready var nav_agent   = $NavigationAgent3D

# ==============================
# EXPORTS
# ==============================
@export var Bullet_Scene: PackedScene
@export var speed := 5.0
@export var shoot_range := 12.0
@export var shoot_delay := 0.6
@export var gravity := 20.0

# ==============================
# STATES
# ==============================
var detected := false
var target: Node3D = null
var can_shoot := true

# ==============================
# SEARCH / CHASE
# ==============================
var last_player_pos := Vector3.ZERO
var searching_lost_player := false
var search_timer := 0.0
var max_search_time := 2.0
var chase_speed_multiplier := 1.35
var search_arrival_dist := 1.0

# ==============================
# HEALTH
# ==============================
var health := 100

# ==============================
# READY
# ==============================
func _ready():
	GameManager.register_enemy()
	primary_gun.show()
	make_watchman_dress()

	nav_agent.path_desired_distance = 0.3
	nav_agent.target_desired_distance = 0.6
	nav_agent.avoidance_enabled = false
	nav_agent.target_position = global_position

# ==============================
# PHYSICS LOOP
# ==============================
func _physics_process(delta):
	if detected and target:
		_detected_behavior(delta)
	elif searching_lost_player:
		_search_behavior(delta)
	else:
		_idle_behavior()

	_apply_gravity(delta)
	move_and_slide()

# ==============================
# IDLE
# ==============================
func _idle_behavior():
	velocity.x = 0
	velocity.z = 0

# ==============================
# DETECTED BEHAVIOR
# ==============================
func _detected_behavior(delta):
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
	_move_along_nav(speed)

# ==============================
# SEARCH BEHAVIOR
# ==============================
func _search_behavior(delta):
	search_timer += delta

	nav_agent.target_position = last_player_pos
	_move_along_nav(speed * chase_speed_multiplier)

	if global_position.distance_to(last_player_pos) <= search_arrival_dist:
		velocity.x = 0
		velocity.z = 0

		if search_timer >= max_search_time:
			searching_lost_player = false

# ==============================
# NAVIGATION MOVEMENT (GODOT 4 CORRECT)
# ==============================
func _move_along_nav(move_speed: float):
	if nav_agent.is_navigation_finished():
		velocity.x = 0
		velocity.z = 0
		return

	var next_pos = nav_agent.get_next_path_position()
	var dir = next_pos - global_position
	dir.y = 0

	if dir.length() < 0.05:
		velocity.x = 0
		velocity.z = 0
		return

	dir = dir.normalized()
	velocity.x = dir.x * move_speed
	velocity.z = dir.z * move_speed

# ==============================
# AREA3D DETECTION
# ==============================
func _on_area_3d_body_entered(body):
	if not body.is_in_group("player"):
		return

	target = body
	detected = true
	searching_lost_player = false
	search_timer = 0.0
	last_player_pos = body.global_position

func _on_area_3d_body_exited(body):
	if body != target:
		return

	detected = false
	target = null
	searching_lost_player = true
	search_timer = 0.0

# ==============================
# ROTATION
# ==============================
func _rotate_to(body):
	var pos = body.global_position
	pos.y = global_position.y
	look_at(pos, Vector3.UP)

# ==============================
# SHOOTING (DOWNED-AWARE AIM)
# ==============================
func _shoot():
	can_shoot = false

	var bullet = Bullet_Scene.instantiate()
	bullet.global_transform = p_muzzle.global_transform

	var aim_point = _get_aim_point(target)
	bullet.direction = (aim_point - p_muzzle.global_position).normalized()

	get_tree().current_scene.add_child(bullet)

	await get_tree().create_timer(shoot_delay).timeout
	can_shoot = true

func _get_aim_point(t: Node3D) -> Vector3:
	var aim_pos = t.global_position

	if "state" in t and t.state == t.PlayerState.DOWNED:
		aim_pos.y -= 0.5   # same behavior as cop

	return aim_pos

# ==============================
# WATCHMAN DRESS (ONLY DIFFERENCE)
# ==============================
func make_watchman_dress():
	var bean = $mesh/bean
	_set_color(bean.get_node("Sphere"), Color(0.4, 0.6, 1.0))        # shirt
	_set_color(bean.get_node("Sphere_003"), Color(0.05, 0.05, 0.1)) # pants
	_set_color(bean.get_node("Torus"), Color(0, 0, 0))              # belt / cap

func _set_color(mesh, color):
	if mesh == null or mesh.mesh == null:
		return
	for i in range(mesh.mesh.get_surface_count()):
		var mat = mesh.get_active_material(i)
		if mat:
			var new_mat = mat.duplicate()
			new_mat.albedo_color = color
			mesh.set_surface_override_material(i, new_mat)

# ==============================
# GRAVITY
# ==============================
func _apply_gravity(delta):
	if not is_on_floor():
		velocity.y -= gravity * delta

# ==============================
# DAMAGE
# ==============================
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
