extends CharacterBody3D

# ==============================
# NODE REFERENCES
# ==============================
@onready var pivot        = $pivot
@onready var primary_gun  = $pivot/primary_gun
@onready var p_muzzle     = $pivot/primary_gun/gun_muzzle
@onready var vision_area  = $pivot/Area3D
@onready var agent        = $NavigationAgent3D

# ---- LOW RAYS ONLY ----
@onready var ray_f_low = $Ray_F_Low
@onready var ray_l_low = $Ray_L_Low
@onready var ray_r_low = $Ray_R_Low
@onready var ray_b_low = $Ray_B_Low

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
# STUCK HANDLING
# ==============================
var stuck_time := 0.0
var stuck_limit := 0.4
var is_stuck := false

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
	agent.avoidance_enabled = false

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
	_rotate_to(target)

	var dist := global_position.distance_to(target.global_position)

	if dist <= shoot_range:
		velocity = Vector3.ZERO
		if can_shoot:
			_shoot()
		return

	_move(target.global_position)

# ==============================
# MOVEMENT (NAV + RAY + STUCK)
# ==============================
func _move(target_pos: Vector3):
	agent.target_position = target_pos

	var next = agent.get_next_path_position()
	var move_dir = (next - global_position)
	move_dir.y = 0.0

	var forward = -pivot.global_transform.basis.z.normalized()
	var right   =  pivot.global_transform.basis.x.normalized()
	var left    = -right
	var back    =  pivot.global_transform.basis.z.normalized()

	if move_dir.length() > 0.01:
		move_dir = move_dir.normalized()
	else:
		move_dir = forward

	var front_blocked = ray_f_low.is_colliding() and not _is_step(ray_f_low)
	var left_blocked  = ray_l_low.is_colliding() and not _is_step(ray_l_low)
	var right_blocked = ray_r_low.is_colliding() and not _is_step(ray_r_low)
	var back_blocked  = ray_b_low.is_colliding() and not _is_step(ray_b_low)

	if is_stuck:
		if not front_blocked or not left_blocked or not right_blocked or not back_blocked:
			is_stuck = false
			stuck_time = 0.0

	if front_blocked and not left_blocked:
		move_dir = (forward + left * 1.2).normalized()

	elif front_blocked and not right_blocked:
		move_dir = (forward + right * 1.2).normalized()

	elif front_blocked and right_blocked and not left_blocked:
		move_dir = left

	elif front_blocked and left_blocked and not right_blocked:
		move_dir = right

	elif left_blocked and right_blocked and not front_blocked:
		move_dir = forward

	elif front_blocked:
		move_dir = forward * 0.5

	elif left_blocked and not right_blocked:
		move_dir = (move_dir + right * 0.8).normalized()

	elif right_blocked and not left_blocked:
		move_dir = (move_dir + left * 0.8).normalized()

	elif front_blocked and left_blocked and right_blocked and not back_blocked:
		move_dir = back

	move_dir += _apply_separation() * separation_strength

	if move_dir.length() < 0.2:
		stuck_time += get_physics_process_delta_time()
	else:
		stuck_time = 0.0
		is_stuck = false

	if stuck_time >= stuck_limit:
		is_stuck = true
		velocity.x = 0
		velocity.z = 0
		return

	move_dir = move_dir.normalized()
	velocity.x = move_dir.x * speed
	velocity.z = move_dir.z * speed

# ==============================
# IGNORE "steps" COLLISION
# ==============================
func _is_step(ray: RayCast3D) -> bool:
	var c = ray.get_collider()
	return c and c.is_in_group("steps")

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

# ==============================
# SHOOTING
# ==============================
func _shoot():
	can_shoot = false

	var bullet = Bullet_Scene.instantiate()
	bullet.global_transform = p_muzzle.global_transform
	bullet.direction = (target.global_position - p_muzzle.global_position).normalized()
	get_tree().current_scene.add_child(bullet)

	await get_tree().create_timer(shoot_delay).timeout
	can_shoot = true

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
