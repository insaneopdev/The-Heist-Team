extends CharacterBody3D

# ==============================
# NODE REFERENCES
# ==============================
@onready var pivot       = $pivot
@onready var primary_gun = $pivot/primary_gun
@onready var p_muzzle    = $pivot/primary_gun/gun_muzzle
@onready var vision_area = $pivot/Area3D
@onready var agent       = $NavigationAgent3D

# --- LOW RAYS ONLY ---
@onready var ray_f_low  = $Ray_F_Low
@onready var ray_l_low  = $Ray_L_Low
@onready var ray_r_low  = $Ray_R_Low
@onready var ray_b_low  = $Ray_B_Low

# ==============================
# EXPORTS
# ==============================
@export var Bullet_Scene: PackedScene
@export var speed := 4.0
@export var shoot_range := 5.0
@export var shoot_delay := 0.6
@export var gravity := 20.0

@export var separation_radius := 1.2
@export var separation_strength := 1.1

# ==============================
# STATE
# ==============================
var detected := false
var target: Node3D
var can_shoot := true
var health := 100

var last_player_pos := Vector3.ZERO
var searching_lost_player := false
var search_timer := 0.0
var max_search_time := 2.0

# ==============================
# STUCK HANDLING
# ==============================
var stuck_time := 0.0
var stuck_limit := 0.4

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

	agent.path_desired_distance = 0.5
	agent.target_desired_distance = 0.5
	agent.avoidance_enabled = false
	
	# Setup raycasts
	_setup_raycasts()

func _setup_raycasts():
	# Make sure raycasts are enabled and have proper collision detection
	for ray in [ray_f_low, ray_l_low, ray_r_low, ray_b_low]:
		if ray:
			ray.enabled = true
			ray.exclude_parent = true

# ==============================
# PHYSICS LOOP
# ==============================
func _physics_process(delta):
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	_apply_gravity(delta)

	if detected:
		_detected_behavior(delta)
	elif searching_lost_player:
		_search_behavior(delta)
	else:
		_idle_behavior()

	move_and_slide()

# ==============================
# IDLE
# ==============================
func _idle_behavior():
	velocity.x = 0
	velocity.z = 0

# ==============================
# DETECTED
# ==============================
func _detected_behavior(delta: float):
	target = _get_nearest_player()
	if not target or not is_instance_valid(target):
		detected = false
		searching_lost_player = true
		search_timer = 0
		return

	last_player_pos = target.global_position
	_rotate_to(target)

	var distance_to_target = global_position.distance_to(target.global_position)
	if distance_to_target <= shoot_range:
		velocity = Vector3.ZERO
		if can_shoot:
			_shoot()
		return

	_move(target.global_position, delta)

# ==============================
# SEARCH
# ==============================
func _search_behavior(delta: float):
	search_timer += delta
	
	# If we have a last known position, move to it
	if last_player_pos != Vector3.ZERO:
		_move(last_player_pos, delta)
		
		# Check if we've reached the search position or time is up
		if global_position.distance_to(last_player_pos) < 1.0 or search_timer >= max_search_time:
			searching_lost_player = false
			last_player_pos = Vector3.ZERO
			search_timer = 0.0

# ==============================
# MOVEMENT (NAV + RAY + STUCK)
# ==============================
func _move(target_pos: Vector3, delta: float):
	# Set navigation target
	agent.target_position = target_pos
	
	# Wait for navigation to update
	await get_tree().process_frame
	
	# Get next path position
	var next_pos = agent.get_next_path_position()
	var move_dir = (next_pos - global_position)
	move_dir.y = 0.0
	
	# Get directional vectors from pivot (enemy faces -Z)
	var forward = -pivot.global_transform.basis.z.normalized()
	var right   = pivot.global_transform.basis.x.normalized()
	var left    = -right
	var back    = -forward  # Since forward is -Z, back is +Z
	
	# Normalize move direction if it's significant
	if move_dir.length() > 0.01:
		move_dir = move_dir.normalized()
	else:
		# If no movement from nav, use forward direction
		move_dir = forward
	
	# Check raycast collisions
	var front_blocked = ray_f_low.is_colliding() and not _is_step(ray_f_low)
	var left_blocked  = ray_l_low.is_colliding() and not _is_step(ray_l_low)
	var right_blocked = ray_r_low.is_colliding() and not _is_step(ray_r_low)
	var back_blocked  = ray_b_low.is_colliding() and not _is_step(ray_b_low)
	
	# Obstacle avoidance logic
	if front_blocked:
		if not left_blocked:
			# Favor going left if front is blocked
			move_dir = (forward + left * 1.5).normalized()
		elif not right_blocked:
			# Try right if left is also blocked
			move_dir = (forward + right * 1.5).normalized()
		elif not back_blocked:
			# Back up if all front directions are blocked
			move_dir = back
		else:
			# Completely stuck, try to rotate
			move_dir = left
	
	elif left_blocked and not right_blocked:
		# Avoid left obstacle
		move_dir = (move_dir + right * 0.5).normalized()
	
	elif right_blocked and not left_blocked:
		# Avoid right obstacle
		move_dir = (move_dir + left * 0.5).normalized()
	
	# Apply separation from other enemies
	move_dir += _apply_separation() * separation_strength
	
	# Stuck detection
	if move_dir.length() < 0.1 and velocity.length() < 0.1:
		stuck_time += delta
	else:
		stuck_time = 0.0
	
	# If stuck, try different direction
	if stuck_time >= stuck_limit:
		stuck_time = 0.0
		# Try moving perpendicular to current direction
		move_dir = left if randf() > 0.5 else right
		# Add some randomness
		move_dir = move_dir.rotated(Vector3.UP, randf_range(-PI/4, PI/4))
	
	# Apply movement
	move_dir = move_dir.normalized()
	velocity.x = move_dir.x * speed
	velocity.z = move_dir.z * speed
	
	# Rotate to face movement direction (but only if moving significantly)
	if velocity.length() > 0.5:
		var look_dir = Vector3(velocity.x, 0, velocity.z).normalized()
		if look_dir.length() > 0.01:
			pivot.look_at(global_position - look_dir, Vector3.UP)

# ==============================
# GROUP FILTER FUNCTION
# ==============================
func _is_step(ray: RayCast3D) -> bool:
	var c = ray.get_collider()
	return c and c.is_in_group("steps")

# ==============================
# TARGETING
# ==============================
func _get_nearest_player() -> Node3D:
	var best: Node3D
	var best_d := INF

	for p in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(p):
			continue
		# Check line of sight
		var space_state = get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(
			global_position + Vector3.UP * 0.5,  # Slightly above ground
			p.global_position + Vector3.UP * 0.5
		)
		query.exclude = [self]
		var result = space_state.intersect_ray(query)
		
		# If we have direct line of sight or hit the player
		if result.is_empty() or result.collider == p:
			var d := global_position.distance_to(p.global_position)
			if d < best_d:
				best_d = d
				best = p

	return best

# ==============================
# AREA DETECTION
# ==============================
func _on_Area3D_body_entered(body):
	if not body.is_in_group("player"):
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	if not AlertManager.alert_active:
		AlertManager.raise_alert(body.global_position)

	target = body
	detected = true
	searching_lost_player = false
	search_timer = 0
	last_player_pos = body.global_position

func _on_Area3D_body_exited(body):
	if body != target:
		return

	detected = false
	target = null
	searching_lost_player = true
	search_timer = 0
	# Keep last_player_pos for searching

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
	if not target or not is_instance_valid(target):
		return
	
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
	else:
		# Keep slight downward velocity to stay on floor
		velocity.y = -0.1

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
	var count := 0
	
	for e in get_tree().get_nodes_in_group("enemy"):
		if e == self or not is_instance_valid(e):
			continue
		var d := global_position.distance_to(e.global_position)
		if d < separation_radius and d > 0:
			force += (global_position - e.global_position).normalized() * (separation_radius - d)
			count += 1
	
	if count > 0:
		force /= count
	
	return force

# ==============================
# VISUALS
# ==============================
func make_watchman_dress():
	var bean = $mesh/bean
	if bean:
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
