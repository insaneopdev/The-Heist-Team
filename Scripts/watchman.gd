extends CharacterBody3D

# ==============================
# NODE REFERENCES
# ==============================
@onready var pivot        = $pivot
@onready var primary_gun  = $pivot/primary_gun
@onready var p_muzzle     = $pivot/primary_gun/gun_muzzle
@onready var vision_area  = $pivot/Area3D
@onready var agent        = $NavigationAgent3D

# ==============================
# EXPORTS
# ==============================
@export var Bullet_Scene: PackedScene
@export var speed := 6.0
@export var shoot_range := 6.0
@export var shoot_delay := 0.25   # 🔥 PANIC FIRE (faster than cop)
@export var gravity := 20.0
@export var acceleration := 8.0

# ==============================
# WATCHMAN BEHAVIOR
# ==============================
@export var leash_distance := 10.0
@export var alert_ping_interval := 1.5

# ==============================
# STATE
# ==============================
var target: Node3D
var can_shoot := true
var health := 100
var nearby_players: Array[Node3D] = []

var spawn_position: Vector3
var alert_timer := 0.0

var _los_cache := false
var _los_timer := 0.0
var _los_interval := 0.03   # 🔥 FAST REACTION (panic)

# ==============================
# READY
# ==============================
func _ready():
	GameManager.register_enemy()
	add_to_group("enemy")

	primary_gun.show()
	make_watchman_dress()

	vision_area.monitoring = true
	vision_area.monitorable = true

	agent.path_desired_distance = 1.0
	agent.target_desired_distance = 1.0
	agent.avoidance_enabled = false

	spawn_position = global_position

# ==============================
# PHYSICS PROCESS
# ==============================
func _physics_process(delta):
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# 🔒 TERRITORY CONTROL (does not over-chase)
	if global_position.distance_to(spawn_position) > leash_distance:
		_move_via_navigation(delta, spawn_position)
		_rotate_to_movement(velocity)
		move_and_slide()
		return

	# Target acquisition
	target = _get_priority_target()

	if target and is_instance_valid(target):
		_attack_behavior(delta)
	else:
		velocity.x = move_toward(velocity.x, 0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0, acceleration * delta)

	# 🔥 CONTINUOUS ALERT PRESSURE
	if target and multiplayer.is_server():
		alert_timer -= delta
		if alert_timer <= 0.0:
			AlertManager.raise_alert(target.global_position)
			alert_timer = alert_ping_interval

	move_and_slide()

# ==============================
# ATTACK & MOVEMENT
# ==============================
func _attack_behavior(delta):
	var dist := global_position.distance_to(target.global_position)

	# 🔥 IMMEDIATE EXECUTION OF DOWNED PLAYER
	if "state" in target and target.state == target.PlayerState.DOWNED:
		_rotate_to(target)
		if can_shoot:
			_shoot()
		return

	# LOS cache
	_los_timer -= delta
	if _los_timer <= 0.0:
		_los_cache = has_los_to_target(target)
		_los_timer = _los_interval

	if _los_cache:
		_rotate_to(target)

		if dist > shoot_range:
			_move_via_navigation(delta, target.global_position)
		else:
			velocity.x = move_toward(velocity.x, 0, acceleration * delta)
			velocity.z = move_toward(velocity.z, 0, acceleration * delta)
			if can_shoot:
				_shoot()
	else:
		if dist > 2.0:
			_move_via_navigation(delta, target.global_position)
			if velocity.length() > 0.1:
				_rotate_to_movement(velocity)

# ==============================
# NAVIGATION
# ==============================
func _move_via_navigation(delta, target_pos):
	agent.target_position = target_pos

	if agent.is_navigation_finished():
		velocity.x = move_toward(velocity.x, 0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0, acceleration * delta)
		return

	var next_pos = agent.get_next_path_position()
	var dir = next_pos - global_position
	dir.y = 0
	dir = dir.normalized()

	velocity.x = move_toward(velocity.x, dir.x * speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, acceleration * delta)

# ==============================
# ROTATION
# ==============================
func _rotate_to(body: Node3D):
	var pos := body.global_position
	pos.y = global_position.y
	look_at(pos, Vector3.UP)

func _rotate_to_movement(vel: Vector3):
	if vel.length() > 0.1:
		var target_y = atan2(vel.x, vel.z)
		rotation.y = lerp_angle(rotation.y, target_y, 0.15)

# ==============================
# SHOOTING (PANIC SPRAY)
# ==============================
func _shoot():
	can_shoot = false

	var bullet = Bullet_Scene.instantiate()
	bullet.global_transform = p_muzzle.global_transform
	bullet.direction = (_get_aim_point(target) - p_muzzle.global_position).normalized()
	get_tree().current_scene.add_child(bullet)

	await get_tree().create_timer(shoot_delay).timeout

	if is_instance_valid(self):
		can_shoot = true

func _get_aim_point(t: Node3D) -> Vector3:
	var aim := t.global_position

	# 🔥 PANIC SPREAD (less disciplined than cop)
	var spread := Vector3(
		randf_range(-0.15, 0.15),
		randf_range(-0.1, 0.1),
		randf_range(-0.15, 0.15)
	)
	aim += spread

	if "state" in t and t.state == t.PlayerState.DOWNED:
		aim.y -= 0.6

	return aim

# ==============================
# TARGETING
# ==============================
func _get_priority_target() -> Node3D:
	nearby_players = nearby_players.filter(is_instance_valid)
	if nearby_players.size() > 0:
		return nearby_players[0]
	return null

# ==============================
# VISION CALLBACKS
# ==============================
func _on_Area3D_body_entered(body):
	if body.is_in_group("player"):
		if not nearby_players.has(body):
			nearby_players.append(body)

		if multiplayer.is_server():
			AlertManager.raise_alert(body.global_position)

func _on_Area3D_body_exited(body):
	nearby_players.erase(body)

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
	queue_free()

# ==============================
# VISUALS
# ==============================
func make_watchman_dress():
	if not has_node("mesh/bean"):
		return
	var bean = $mesh/bean
	_set_color(bean.get_node("Sphere"), Color(0.4, 0.6, 1.0))
	_set_color(bean.get_node("Sphere_003"), Color(0.05, 0.05, 0.1))
	_set_color(bean.get_node("Torus"), Color.BLACK)

func _set_color(mesh, color):
	if not mesh or not mesh.mesh:
		return
	for i in mesh.mesh.get_surface_count():
		var mat = mesh.get_active_material(i)
		if mat:
			var nm = mat.duplicate()
			nm.albedo_color = color
			mesh.set_surface_override_material(i, nm)

# ==============================
# LOS
# ==============================
func has_los_to_target(t: Node3D) -> bool:
	var from_pos = global_position + Vector3.UP * 1.2
	var to_pos   = t.global_position + Vector3.UP * 1.2

	var q := PhysicsRayQueryParameters3D.new()
	q.from = from_pos
	q.to = to_pos
	q.exclude = [self]
	q.collision_mask = 1

	var res = get_world_3d().direct_space_state.intersect_ray(q)
	return res.is_empty() or res.collider == t
