extends CharacterBody3D

# ==============================
# SIGNALS
# ==============================
signal died(killer_id)

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
@export var acceleration := 8.0

# ==============================
# STATE
# ==============================
var target: Node3D
var can_shoot := true
var health := 100
var nearby_players: Array[Node3D] = []

# LOS CACHE
var _los_cache := false
var _los_timer := 0.0
var _los_interval := 0.1

# --- DOWNED CONTROL ---
var controlling_downed := false
var downed_target: Node3D = null
var downed_wait_timer := 0.0
var downed_wait_time := 2.0
var decision_made := false
var choose_kill_downed := false
var choose_chase_rescuer := false

# ==============================
# READY
# ==============================
func _ready():
	add_to_group("enemy") # AI ONLY (never used for game logic)

	primary_gun.show()
	make_cop_dress()

	vision_area.monitoring = true
	vision_area.monitorable = true

	agent.path_desired_distance = 1.0
	agent.target_desired_distance = 1.0
	agent.avoidance_enabled = false

# ==============================
# PHYSICS PROCESS
# ==============================
func _physics_process(delta):
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	if not AlertManager.alert_active:
		_stop_motion(delta)
		move_and_slide()
		return

	if _check_for_downed_player(delta):
		move_and_slide()
		return

	target = _get_priority_target()
	if target:
		_attack_behavior(delta)
	else:
		_stop_motion(delta)

	move_and_slide()

# ==============================
# DOWNED LOGIC
# ==============================
func _check_for_downed_player(delta) -> bool:
	if controlling_downed:
		_handle_downed_control(delta)
		return true

	for p in nearby_players:
		if not is_instance_valid(p): continue
		if "state" in p and p.state == p.PlayerState.DOWNED:
			_start_downed_control(p)
			return true

	return false

func _start_downed_control(p):
	controlling_downed = true
	downed_target = p
	downed_wait_timer = downed_wait_time
	decision_made = false

	if randf() < 0.5:
		_call_nearby_enemies(p.global_position)

func _handle_downed_control(delta):
	if not is_instance_valid(downed_target):
		_reset_downed_control()
		return

	var dist := global_position.distance_to(downed_target.global_position)

	if dist > 2.0:
		_move_via_navigation(delta, downed_target.global_position)
		_rotate_to_movement(velocity)
		return

	_rotate_to(downed_target)
	_stop_motion(delta)

	downed_wait_timer -= delta
	if downed_wait_timer > 0:
		return

	var rescuer = _find_rescuer_near_downed()
	if rescuer:
		if not decision_made:
			_decide_downed_action()
			decision_made = true

		if choose_kill_downed and can_shoot:
			_shoot_target(downed_target)
			_reset_downed_control()
			return

		if choose_chase_rescuer:
			target = rescuer
			_reset_downed_control()
			return

func _decide_downed_action():
	choose_kill_downed = randf() < 0.5
	choose_chase_rescuer = randf() < 0.5

func _find_rescuer_near_downed() -> Node3D:
	for p in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(p): continue
		if p == downed_target: continue
		if global_position.distance_to(p.global_position) < 6.0:
			return p
	return null

func _call_nearby_enemies(pos: Vector3):
	for e in get_tree().get_nodes_in_group("enemy"):
		if e == self: continue
		if global_position.distance_to(e.global_position) < 12.0:
			if randf() < 0.5:
				e.agent.target_position = pos

func _reset_downed_control():
	controlling_downed = false
	downed_target = null
	decision_made = false

# ==============================
# COMBAT
# ==============================
func _attack_behavior(delta):
	var dist := global_position.distance_to(target.global_position)

	_los_timer -= delta
	if _los_timer <= 0:
		_los_cache = has_los_to_target(target)
		_los_timer = _los_interval

	if _los_cache:
		_rotate_to(target)
		if dist > shoot_range:
			_move_via_navigation(delta, target.global_position)
		else:
			_stop_motion(delta)
			if can_shoot:
				_shoot()
		return

	if dist > 2.0:
		_move_via_navigation(delta, target.global_position)
		_rotate_to_movement(velocity)
	else:
		_stop_motion(delta)

# ==============================
# MOVEMENT HELPERS
# ==============================
func _move_via_navigation(delta, pos):
	agent.target_position = pos
	if agent.is_navigation_finished():
		_stop_motion(delta)
		return

	var next_pos = agent.get_next_path_position()
	var dir = (next_pos - global_position).normalized()
	velocity.x = move_toward(velocity.x, dir.x * speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, acceleration * delta)

func _stop_motion(delta):
	velocity.x = move_toward(velocity.x, 0, acceleration * delta)
	velocity.z = move_toward(velocity.z, 0, acceleration * delta)

func _rotate_to(body):
	if not is_instance_valid(body): return
	var p = body.global_position
	p.y = global_position.y
	look_at(p, Vector3.UP)

func _rotate_to_movement(v):
	if v.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(v.x, v.z), 0.1)

# ==============================
# SHOOTING
# ==============================
func _shoot():
	_shoot_target(target)

func _shoot_target(t):
	if not can_shoot or not is_instance_valid(t): return
	can_shoot = false

	var bullet = Bullet_Scene.instantiate()
	bullet.global_transform = p_muzzle.global_transform
	bullet.direction = (t.global_position - p_muzzle.global_position).normalized()
	get_tree().current_scene.add_child(bullet)

	await get_tree().create_timer(shoot_delay).timeout
	can_shoot = true

# ==============================
# TARGETING
# ==============================
func _get_priority_target() -> Node3D:
	if nearby_players.size() > 0:
		return nearby_players[0]
	return _get_nearest_player()

func _get_nearest_player() -> Node3D:
	var best
	var best_d := INF
	for p in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(p): continue
		var d := global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best

func _on_Area3D_body_entered(body):
	if body.is_in_group("player"):
		nearby_players.append(body)

func _on_Area3D_body_exited(body):
	nearby_players.erase(body)

# ==============================
# DAMAGE / DEATH
# ==============================
@rpc("any_peer", "call_local")
func receive_damage(amount, attacker_id):
	health -= amount
	if health <= 0:
		die(attacker_id)

func die(killer_id):
	if multiplayer.is_server():
		emit_signal("died", killer_id)
	queue_free()

# ==============================
# VISUALS
# ==============================
func make_cop_dress():
	if not has_node("mesh/bean"): return
	var bean = $mesh/bean
	_set_color(bean.get_node("Sphere"), Color(0, 0.1, 0.3))
	_set_color(bean.get_node("Sphere_003"), Color(0, 0.1, 0.3))
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
# LINE OF SIGHT
# ==============================
func has_los_to_target(t) -> bool:
	if not is_instance_valid(t): return false
	var q := PhysicsRayQueryParameters3D.new()
	q.from = global_position + Vector3.UP * 1.2
	q.to = t.global_position + Vector3.UP * 1.2
	q.exclude = [self]
	var r = get_world_3d().direct_space_state.intersect_ray(q)
	return r.is_empty() or r.collider == t
