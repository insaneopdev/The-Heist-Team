extends CharacterBody3D

# ==============================
# NODE REFERENCES
# ==============================
@onready var pivot       = $pivot
@onready var primary_gun = $pivot/primary_gun
@onready var p_muzzle    = $pivot/primary_gun/gun_muzzle
@onready var vision_area = $pivot/Area3D
@onready var agent       = $NavigationAgent3D

# --- RAYS ---
@onready var ray_f_high = $Ray_F_High
@onready var ray_l_high = $Ray_L_High
@onready var ray_r_high = $Ray_R_High
@onready var ray_f_low  = $Ray_F_Low
@onready var ray_l_low  = $Ray_L_Low
@onready var ray_r_low  = $Ray_R_Low

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

# ==============================
# PHYSICS LOOP
# ==============================
func _physics_process(delta):
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	_apply_gravity(delta)

	if detected:
		_detected_behavior()
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
func _detected_behavior():
	target = _get_nearest_player()
	if not target:
		return

	last_player_pos = target.global_position
	_rotate_to(target)

	if global_position.distance_to(target.global_position) <= shoot_range:
		velocity.x = 0
		velocity.z = 0
		if can_shoot:
			_shoot()
		return

	_move(target.global_position)

# ==============================
# SEARCH
# ==============================
func _search_behavior(delta):
	search_timer += delta
	_move(last_player_pos)

	if global_position.distance_to(last_player_pos) < 1.0:
		velocity = Vector3.ZERO
		if search_timer >= max_search_time:
			searching_lost_player = false

# ==============================
# NAVIGATE + RAYCAST AVOIDANCE
# ==============================
func _move(target_pos: Vector3):
	agent.target_position = target_pos
	var next = agent.get_next_path_position()
	var move_dir = (next - global_position)
	move_dir.y = 0

	# If no path movement, default to forward (-Z)
	if move_dir.length() > 0.01:
		move_dir = move_dir.normalized()
	else:
		move_dir = -pivot.global_transform.basis.z.normalized()

	# ---- RAY AVOIDANCE ----
	var avoid := Vector3.ZERO

	if ray_f_low.is_colliding():
		avoid += ray_f_low.get_collision_normal()
	if ray_l_low.is_colliding():
		avoid += ray_l_low.get_collision_normal() * 0.4
	if ray_r_low.is_colliding():
		avoid += ray_r_low.get_collision_normal() * 0.4

	avoid.y = 0

	if avoid != Vector3.ZERO:
		var slid = move_dir.slide(avoid.normalized())
		if slid.dot(move_dir) > 0:
			move_dir = slid
		else:
			move_dir = (pivot.global_transform.basis.x * sign(randf() - 0.5)).normalized()

	# ---- FORCE FORWARD (-Z) ----
	var forward = -pivot.global_transform.basis.z.normalized()
	move_dir = (move_dir + forward * 0.15).normalized()

	# ---- SEPARATION ----
	move_dir += _apply_separation() * separation_strength
	move_dir = move_dir.normalized()

	# ---- APPLY ----
	velocity.x = move_dir.x * speed
	velocity.z = move_dir.z * speed

# ==============================
# TARGET SELECTION
# ==============================
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
func make_watchman_dress():
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
