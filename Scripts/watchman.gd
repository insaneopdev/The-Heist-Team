extends CharacterBody3D

# ==============================
# NODE REFERENCES
# ==============================
@onready var pivot        = $pivot
@onready var primary_gun  = $pivot/primary_gun
@onready var p_muzzle     = $pivot/primary_gun/gun_muzzle
@onready var vision_area  = $pivot/Area3D
@onready var agent        = $NavigationAgent3D

# --- EXTRACTION SHOOTER VSX ---
var strafe_dir := 1.0
var strafe_timer := 0.0

# ==============================
# EXPORTS
# ==============================
@export var speed := 6.0
@export var shoot_range := 6.0
@export var shoot_delay := 0.5
@export var gravity := 20.0
@export var acceleration := 8.0
@export var damage := 10

# ==============================
# STATE
# ==============================
var target: Node3D
var can_shoot := true
var health := 100
var nearby_players: Array[Node3D] = []

var _los_cache := false
var _los_timer := 0.0
var _los_interval := 0.1

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

	# NAVIGATION SETUP
	agent.path_desired_distance = 1.0
	agent.target_desired_distance = 1.0
	agent.avoidance_enabled = false

# ==============================
# PHYSICS PROCESS
# ==============================
func _physics_process(delta):
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# 🔥 WATCHMAN LOGIC CHANGE
	# Watchman reacts ONLY if it personally has a target
	target = _get_priority_target()

	if target and is_instance_valid(target):
		_attack_behavior(delta)
	else:
		# Idle / calm behavior
		velocity.x = move_toward(velocity.x, 0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0, acceleration * delta)

	# 4. Crowd Avoidance
	_apply_crowd_avoidance(delta)

	move_and_slide()

# ==============================
# ATTACK & MOVEMENT
# ==============================
func _attack_behavior(delta):
	var dist := global_position.distance_to(target.global_position)

	# LOS cache
	_los_timer -= delta
	if _los_timer <= 0.0:
		_los_cache = has_los_to_target(target)
		_los_timer = _los_interval

	var los := _los_cache

	# CASE A: HAS LOS
	if los:
		_rotate_to(target)

		if dist > shoot_range:
			_move_via_navigation(delta, target.global_position)
		else:
			_combat_strafe(delta)
			if can_shoot:
				_shoot()
		return

	# CASE B: LOST LOS → MOVE TO LAST KNOWN
	if dist > 2.0:
		_move_via_navigation(delta, target.global_position)
		if velocity.length() > 0.1:
			_rotate_to_movement(velocity)
	else:
		velocity.x = move_toward(velocity.x, 0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0, acceleration * delta)

func _combat_strafe(delta):
	strafe_timer -= delta
	if strafe_timer <= 0:
		strafe_dir *= -1
		strafe_timer = randf_range(0.5, 1.5)
	
	var side_vec = global_transform.basis.x * strafe_dir * (speed * 0.7)
	velocity.x = move_toward(velocity.x, side_vec.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, side_vec.z, acceleration * delta)

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
	if not is_instance_valid(body): return
	var pos := body.global_position
	pos.y = global_position.y
	if global_position.is_equal_approx(pos): return
	look_at(pos, Vector3.UP)

func _rotate_to_movement(vel: Vector3):
	if vel.length() > 0.1:
		var target_y = atan2(vel.x, vel.z)
		rotation.y = lerp_angle(rotation.y, target_y, 0.1)

# ==============================
# SHOOTING
# ==============================
func _shoot():
	can_shoot = false

	# Broadcast shoot visuals and trigger hitscan on the server
	rpc("sync_shoot", _get_aim_point(target))

	await get_tree().create_timer(shoot_delay).timeout

	if is_instance_valid(self):
		can_shoot = true

@rpc("call_local", "authority")
func sync_shoot(aim_target: Vector3):
	# --- 1. VISUALS (Runs on all clients) ---
	var f = OmniLight3D.new()
	f.light_color = Color.YELLOW
	f.omni_range = 2.5
	p_muzzle.add_child(f)
	
	# Temporary muzzle flash cleanup
	get_tree().create_timer(0.05).timeout.connect(func():
		if is_instance_valid(f): f.queue_free()
	)

	# --- 2. HITSCAN LOGIC (Server Only) ---
	if multiplayer.is_server():
		var space_state = get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(p_muzzle.global_position, aim_target)
		query.exclude = [self]
		query.collision_mask = 1 # Assuming default mask hits players/world
		
		var result = space_state.intersect_ray(query)
		if result and result.collider:
			if result.collider.is_in_group("player") and result.collider.has_method("receive_damage"):
				# Tell the player they took damage
				result.collider.rpc("receive_damage", damage)

func _get_aim_point(t: Node3D) -> Vector3:
	var aim = t.global_position
	if "state" in t and t.state == t.PlayerState.DOWNED:
		aim.y -= 0.5
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

		# 🔥 Watchman raises alert, but does NOT obey it
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
	set_physics_process(false)
	if has_node("CollisionShape3D"):
		$CollisionShape3D.set_deferred("disabled", true)
		
	if multiplayer.is_server():
		GameManager.enemy_died()
		GameManager.add_kill(killer_id)
		rpc("_sync_death_juice")
	
	# Wait a tiny bit for the 'pop' before freeing
	await get_tree().create_timer(0.1).timeout
	queue_free()

@rpc("call_local", "authority")
func _sync_death_juice():
	# Visual 'Death Pop'
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector3(0.001, 0.001, 0.001), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)

# ==============================
# VISUALS
# ==============================
func make_watchman_dress():
	if not has_node("mesh/bean"): return
	var bean = $mesh/bean
	_set_color(bean.get_node("Sphere"), Color(0.4, 0.6, 1.0))
	_set_color(bean.get_node("Sphere_003"), Color(0.05, 0.05, 0.1))
	_set_color(bean.get_node("Torus"), Color.BLACK)

func _set_color(mesh, color):
	if not mesh or not mesh.mesh: return
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

func _apply_crowd_avoidance(delta):
	for other in get_tree().get_nodes_in_group("enemy"):
		if other == self: continue
		var dist = global_position.distance_to(other.global_position)
		if dist < 1.4:
			var push_dir = other.global_position.direction_to(global_position)
			push_dir.y = 0
			if push_dir.length() < 0.01:
				push_dir = Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0)).normalized()
			
			var strength = (1.4 - dist) * 10.0
			velocity.x += push_dir.x * strength * delta
			velocity.z += push_dir.z * strength * delta
