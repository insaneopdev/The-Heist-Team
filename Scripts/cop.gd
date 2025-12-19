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
@export var shoot_delay := 0.5
@export var gravity := 20.0

@export var separation_radius := 1.4
@export var separation_strength := 1.1

# ==============================
# STATE
# ==============================
var target: Node3D
var can_shoot := true
var health := 100
var nearby_players: Array[Node3D] = []

# ==============================
# READY
# ==============================
func _ready():
	GameManager.register_enemy()
	add_to_group("enemy")
	primary_gun.show()
	make_cop_dress()

	vision_area.monitoring = true
	vision_area.monitorable = true

	agent.path_desired_distance = 0.4
	agent.target_desired_distance = 0.4
	agent.avoidance_enabled = true

# ==============================
# PHYSICS
# ==============================
func _physics_process(delta):
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	_apply_gravity(delta)

	if not AlertManager.alert_active:
		velocity.x = 0
		velocity.z = 0
		move_and_slide()
		return

	target = _get_priority_target()
	if target:
		_attack_behavior()

	move_and_slide()

# ==============================
# ATTACK
# ==============================
func _attack_behavior():
	var dist := global_position.distance_to(target.global_position)
	var los := has_los_to_target(target)

	# ░░░ LOS VALID → rotate to player ░░░
	if los:
		_rotate_to(target)
	else:
		# ░░░ LOS BLOCKED → rotate to nav direction instead ░░░
		var next = agent.get_next_path_position()
		var move_dir = (next - global_position)
		move_dir.y = 0.0
		_rotate_to_movement(move_dir)

	if los:
		if dist <= shoot_range:
			velocity = Vector3.ZERO
			if can_shoot:
				_shoot()
			return
		else:
			_move(target.global_position)
			return

	if dist > 2.0:
		_move(target.global_position)
	else:
		velocity = Vector3.ZERO

# ==============================
# MOVEMENT (NAV + SEPARATION)
# ==============================
func _move(target_pos: Vector3):
	agent.target_position = target_pos

	var next = agent.get_next_path_position()
	var move_dir = (next - global_position)
	move_dir.y = 0.0

	if move_dir.length() > 0.01:
		move_dir = move_dir.normalized()
	else:
		move_dir = -pivot.global_transform.basis.z.normalized()

	# separation
	move_dir += _apply_separation() * separation_strength
	move_dir = move_dir.normalized()

	velocity.x = move_dir.x * speed
	velocity.z = move_dir.z * speed

# ==============================
# TARGETING
# ==============================
func _get_priority_target() -> Node3D:
	if nearby_players.size() > 0:
		return nearby_players[0]
	return _get_nearest_player()

func _get_nearest_player() -> Node3D:
	var best: Node3D
	var best_d := INF

	for p in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(p):
			continue
		var d := global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p

	return best

# ==============================
# AREA EVENTS
# ==============================
func _on_Area3D_body_entered(body):
	if body.is_in_group("player"):
		nearby_players.append(body)

func _on_Area3D_body_exited(body):
	nearby_players.erase(body)

# ==============================
# ROTATION
# ==============================
func _rotate_to(body: Node3D):
	var pos := body.global_position
	pos.y = global_position.y
	look_at(pos, Vector3.UP)
	
func _rotate_to_movement(move_dir: Vector3):
	if move_dir.length() > 0.1:
		var target_rotation = atan2(move_dir.x, move_dir.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, 0.15)


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


# ==============================
# AIM LOGIC
# ==============================
func _get_aim_point(t: Node3D) -> Vector3:
	if not is_instance_valid(t):
		return p_muzzle.global_position

	var aim_pos = t.global_position

	if "state" in t and t.state == t.PlayerState.DOWNED:
		aim_pos.y -= 0.5

	return aim_pos


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
	queue_free()

# ==============================
# SEPARATION
# ==============================
func _apply_separation() -> Vector3:
	var force := Vector3.ZERO
	for e in get_tree().get_nodes_in_group("enemy"):
		if e == self or not is_instance_valid(e):
			continue
		var d := global_position.distance_to(e.global_position)
		if d < separation_radius:
			force += (global_position - e.global_position).normalized() * (separation_radius - d)
	return force

# ==============================
# VISUALS
# ==============================
func make_cop_dress():
	var bean = $mesh/bean
	_set_color(bean.get_node("Sphere"), Color(0.0, 0.1, 0.3))
	_set_color(bean.get_node("Sphere_003"), Color(0.0, 0.1, 0.3))
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
	if not is_instance_valid(t):
		return false

	var from_pos = global_position + Vector3.UP * 1.2
	var to_pos   = t.global_position + Vector3.UP * 1.2

	var query := PhysicsRayQueryParameters3D.new()
	query.from = from_pos
	query.to = to_pos
	query.exclude = [ self ]  # ignore our own collider

	var result = get_world_3d().direct_space_state.intersect_ray(query)

	if result.is_empty():
		return true
	else:
		return false
