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
@export var Bullet_Scene: PackedScene
@export var speed := 6.0
@export var shoot_range := 6.0
@export var shoot_delay := 0.5
@export var gravity := 20.0
@export var acceleration := 8.0  # Added for smoother movement

# ==============================
# STATE
# ==============================
var target: Node3D
var can_shoot := true
var health := 100
var nearby_players: Array[Node3D] = []

var _los_cache := false
var _los_timer := 0.0
var _los_interval := 0.1 # Increased slightly for performance

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

	# NAVIGATION SETUP
	# These settings prevent the enemy from trying to reach the EXACT pixel
	agent.path_desired_distance = 1.0 
	agent.target_desired_distance = 1.0
	
	# DISABLE AVOIDANCE to stop the jittering
	agent.avoidance_enabled = false 

# ==============================
# PHYSICS PROCESS
# ==============================
func _physics_process(delta):
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	# 1. Apply Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# 2. Check Alert State
	if not AlertManager.alert_active:
		# Slow down to a stop if not alerted
		velocity.x = move_toward(velocity.x, 0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0, acceleration * delta)
		move_and_slide()
		return

	# 3. Find Target
	target = _get_priority_target()
	
	if target:
		_attack_behavior(delta)
	else:
		# No target, stop moving
		velocity.x = move_toward(velocity.x, 0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0, acceleration * delta)

	# 4. Crowd Avoidance (Fixes bottlenecks at doors)
	_apply_crowd_avoidance(delta)
	
	move_and_slide()

# ==============================
# ATTACK & MOVEMENT LOGIC
# ==============================
func _attack_behavior(delta):
	var dist := global_position.distance_to(target.global_position)

	# --- LOS Check ---
	_los_timer -= delta
	if _los_timer <= 0.0:
		_los_cache = has_los_to_target(target)
		_los_timer = _los_interval
	var los := _los_cache

	# --- BEHAVIOR TREE ---
	
	# Case A: We have clear line of sight
	if los:
		_rotate_to(target)
		
		if dist > shoot_range:
			# Chasing
			_move_via_navigation(delta, target.global_position)
		else:
			# Combat Strafe (Harder to hit)
			_combat_strafe(delta)
			if can_shoot:
				_shoot()
		return

	# Case B: No LOS (Target is hiding or around corner)
	if not los:
		# If we are somewhat far, pathfind to them
		if dist > 2.0:
			_move_via_navigation(delta, target.global_position)
			
			# Face movement direction so he doesn't moonwalk
			if velocity.length() > 0.1:
				_rotate_to_movement(velocity)
		
		# If we are close but can't see them (stuck on wall?), try to shoot anyway or wait
		else:
			velocity.x = move_toward(velocity.x, 0, acceleration * delta)
			velocity.z = move_toward(velocity.z, 0, acceleration * delta)
			
			if _has_short_los_to_target(target, 3.0):
				_rotate_to(target)
				if can_shoot: _shoot()

func _combat_strafe(delta):
	strafe_timer -= delta
	if strafe_timer <= 0:
		strafe_dir *= -1
		strafe_timer = randf_range(0.5, 1.5)
	
	var side_vec = global_transform.basis.x * strafe_dir * (speed * 0.7)
	velocity.x = move_toward(velocity.x, side_vec.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, side_vec.z, acceleration * delta)

# ==============================
# NAVIGATION MOVEMENT
# ==============================
func _move_via_navigation(delta, target_pos):
	# Update target position (throttled check not strictly needed unless laggy)
	agent.target_position = target_pos

	if agent.is_navigation_finished():
		velocity.x = move_toward(velocity.x, 0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0, acceleration * delta)
		return

	# Get the next point on the baked path
	var next_path_position = agent.get_next_path_position()
	var direction = (next_path_position - global_position).normalized()
	
	# Smoothly accelerate towards the direction
	velocity.x = move_toward(velocity.x, direction.x * speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, acceleration * delta)

# ==============================
# ROTATION & HELPERS (Unchanged)
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

func _shoot():
	can_shoot = false
	var bullet = Bullet_Scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.global_transform = p_muzzle.global_transform
	var aim_point = _get_aim_point(target)
	bullet.direction = (aim_point - p_muzzle.global_position).normalized()
	
	# Muzzle Flash
	var f = OmniLight3D.new()
	f.light_color = Color.ORANGE
	f.omni_range = 3.0
	p_muzzle.add_child(f)
	
	await get_tree().create_timer(0.05).timeout
	f.queue_free()
	
	await get_tree().create_timer(shoot_delay - 0.05).timeout
	can_shoot = true

func _get_aim_point(t: Node3D) -> Vector3:
	if not is_instance_valid(t): return p_muzzle.global_position
	var aim_pos = t.global_position
	if "state" in t and t.state == t.PlayerState.DOWNED:
		aim_pos.y -= 0.5
	return aim_pos

func _get_priority_target() -> Node3D:
	if nearby_players.size() > 0: return nearby_players[0]
	return _get_nearest_player()

func _get_nearest_player() -> Node3D:
	var best: Node3D
	var best_d := INF
	for p in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(p): continue
		var d := global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best

func _on_Area3D_body_entered(body):
	if body.is_in_group("player"): nearby_players.append(body)

func _on_Area3D_body_exited(body):
	nearby_players.erase(body)

# DAMAGE / VISUALS
@rpc("any_peer", "call_local")
func receive_damage(amount, attacker_id):
	health -= amount
	if health <= 0: die(attacker_id)

func die(killer_id):
	set_physics_process(false)
	if has_node("CollisionShape3D"):
		$CollisionShape3D.set_deferred("disabled", true)
		
	if multiplayer.is_server():
		GameManager.enemy_died()
		GameManager.add_kill(killer_id)
		rpc("_sync_death_juice")
	
	# Small delay before removal
	await get_tree().create_timer(0.15).timeout
	queue_free()

@rpc("call_local", "authority")
func _sync_death_juice():
	# Death Pop
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector3(0.001, 0.001, 0.001), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)

func make_cop_dress():
	var bean = $mesh/bean
	if has_node("mesh/bean"):
		_set_color(bean.get_node("Sphere"), Color(0.0, 0.1, 0.3))
		_set_color(bean.get_node("Sphere_003"), Color(0.0, 0.1, 0.3))
		_set_color(bean.get_node("Torus"), Color.BLACK)

func _set_color(mesh, color):
	if not mesh or not mesh.mesh: return
	for i in mesh.mesh.get_surface_count():
		var mat = mesh.get_active_material(i)
		if mat:
			var nm = mat.duplicate()
			nm.albedo_color = color
			mesh.set_surface_override_material(i, nm)

func has_los_to_target(t: Node3D) -> bool:
	if not is_instance_valid(t): return false
	var from_pos = global_position + Vector3.UP * 1.2
	var to_pos   = t.global_position + Vector3.UP * 1.2
	var query := PhysicsRayQueryParameters3D.new()
	query.from = from_pos
	query.to = to_pos
	query.exclude = [ self ]
	var result = get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty(): return true
	return result.collider == t
	
func _has_short_los_to_target(t: Node3D, max_dist: float) -> bool:
	if not is_instance_valid(t): return false
	if p_muzzle.global_position.distance_to(t.global_position) > max_dist: return false
	return has_los_to_target(t)

func _apply_crowd_avoidance(delta):
	# Loop through enemies to push away if overlapping (prevents door sticking)
	for other in get_tree().get_nodes_in_group("enemy"):
		if other == self: continue
		var dist = global_position.distance_to(other.global_position)
		if dist < 1.5: # Detection radius
			var push_dir = other.global_position.direction_to(global_position)
			push_dir.y = 0
			if push_dir.length() < 0.01:
				push_dir = Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0)).normalized()
			
			var push_strength = (1.5 - dist) * 12.0
			velocity.x += push_dir.x * push_strength * delta
			velocity.z += push_dir.z * push_strength * delta
