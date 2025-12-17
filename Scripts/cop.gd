extends CharacterBody3D

# =====================================================
# NODE REFERENCES
# =====================================================
@onready var pivot        = $pivot
@onready var primary_gun  = $pivot/primary_gun
@onready var p_muzzle     = $pivot/primary_gun/gun_muzzle
@onready var vision_area  = $pivot/Area3D

# --- RAYS ---
@onready var ray_f_high = $Ray_F_High
@onready var ray_l_high = $Ray_L_High
@onready var ray_r_high = $Ray_R_High
@onready var ray_f_low  = $Ray_F_Low
@onready var ray_l_low  = $Ray_L_Low
@onready var ray_r_low  = $Ray_R_Low

# =====================================================
# EXPORTS
# =====================================================
@export var Bullet_Scene: PackedScene
@export var speed := 7.0
@export var shoot_range := 7.0
@export var shoot_delay := 0.6
@export var gravity := 20.0

@export var separation_radius := 1.2
@export var separation_strength := 1.1

# =====================================================
# STATE
# =====================================================
var target: Node3D
var can_shoot := true
var health := 100
var last_move_dir := Vector3.ZERO

var nearby_players: Array[Node3D] = []

# =====================================================
# READY
# =====================================================
func _ready():
	GameManager.register_enemy()
	add_to_group("enemy")
	primary_gun.show()
	make_cop_dress()

	vision_area.monitoring = true
	vision_area.monitorable = true

# =====================================================
# PHYSICS LOOP
# =====================================================
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

# =====================================================
# ATTACK LOGIC
# =====================================================
func _attack_behavior():
	_rotate_to(target)

	var dist := global_position.distance_to(target.global_position)

	if dist <= shoot_range:
		velocity.x = 0
		velocity.z = 0
		if can_shoot:
			_shoot()
		return

	_move(target.global_position)

# =====================================================
# COLLIDER-CENTRIC MOVEMENT (FIXED)
# =====================================================
func _move(target_pos: Vector3):
	var move_dir := target_pos - global_position
	move_dir.y = 0
	if move_dir.length() < 0.01:
		return
	move_dir = move_dir.normalized()

	var wall_normal := Vector3.ZERO
	if ray_f_low.is_colliding():
		wall_normal += ray_f_low.get_collision_normal()
	if ray_l_low.is_colliding():
		wall_normal += ray_l_low.get_collision_normal()
	if ray_r_low.is_colliding():
		wall_normal += ray_r_low.get_collision_normal()

	wall_normal.y = 0

	if wall_normal != Vector3.ZERO:
		move_dir = move_dir.slide(wall_normal.normalized())

	# 🔥 THIS IS THE FIX 🔥
	if move_dir.length() < 0.05 and wall_normal != Vector3.ZERO:
		var tangent := wall_normal.cross(Vector3.UP).normalized()
		if tangent.dot(target_pos - global_position) < 0:
			tangent = -tangent
		move_dir = tangent

	move_dir += _apply_separation() * separation_strength

	if move_dir.length() < 0.05:
		move_dir = last_move_dir

	last_move_dir = move_dir.normalized()

	velocity.x = last_move_dir.x * speed
	velocity.z = last_move_dir.z * speed

# =====================================================
# TARGET PRIORITY
# =====================================================
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

# =====================================================
# AREA CALLBACKS
# =====================================================
func _on_Area3D_body_entered(body):
	if body.is_in_group("player"):
		nearby_players.append(body)

func _on_Area3D_body_exited(body):
	nearby_players.erase(body)

# =====================================================
# ROTATION
# =====================================================
func _rotate_to(body: Node3D):
	var pos := body.global_position
	pos.y = global_position.y
	look_at(pos, Vector3.UP)

# =====================================================
# SHOOTING
# =====================================================
func _shoot():
	can_shoot = false

	var bullet = Bullet_Scene.instantiate()
	bullet.global_transform = p_muzzle.global_transform
	bullet.direction = (target.global_position - p_muzzle.global_position).normalized()
	get_tree().current_scene.add_child(bullet)

	await get_tree().create_timer(shoot_delay).timeout
	can_shoot = true

# =====================================================
# GRAVITY
# =====================================================
func _apply_gravity(delta):
	if not is_on_floor():
		velocity.y -= gravity * delta

# =====================================================
# DAMAGE
# =====================================================
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

# =====================================================
# VISUALS
# =====================================================
func make_cop_dress():
	var bean = $mesh/bean
	_set_color(bean.get_node("Sphere"), Color(0.0, 0.1, 0.3))
	_set_color(bean.get_node("Sphere_003"), Color(0.0, 0.1, 0.3))
	_set_color(bean.get_node("Torus"), Color.BLACK)

func _set_color(mesh, color):
	if not mesh or not mesh.mesh:
		return
	for i in mesh.mesh.get_surface_count():
		var m = mesh.get_active_material(i)
		if m:
			var nm = m.duplicate()
			nm.albedo_color = color
			mesh.set_surface_override_material(i, nm)
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
