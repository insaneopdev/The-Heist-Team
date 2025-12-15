extends CharacterBody3D

# ==============================
# NODE REFERENCES
# ==============================
@onready var pivot       = $pivot
@onready var primary_gun = $pivot/primary_gun
@onready var p_muzzle    = $pivot/primary_gun/gun_muzzle
@onready var vision_area = $pivot/Area3D   # PRIORITY ONLY (NOT DETECTION)

# ==============================
# EXPORTS
# ==============================
@export var Bullet_Scene: PackedScene
@export var speed := 7.0
@export var shoot_range :=7.0
@export var shoot_delay := 0.6
@export var gravity := 20.0
@export var separation_radius := 1.2
@export var separation_strength := 1.5


# ==============================
# STATE
# ==============================
var target: Node3D = null
var can_shoot := true
var health := 100

# ==============================
# PRIORITY TARGETS
# ==============================
var nearby_players: Array[Node3D] = []

# ==============================
# READY
# ==============================
func _ready():
	GameManager.register_enemy()
	add_to_group("enemy")
	primary_gun.show()
	make_cop_dress()

	# Area3D is ONLY for priority after alert
	vision_area.monitoring = true
	vision_area.monitorable = true

# ==============================
# PHYSICS LOOP
# ==============================
func _physics_process(delta):
	# Server-authoritative AI
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	_apply_gravity(delta)

	# 🔑 HARD GATE: cops do NOTHING until watchman raises alert
	if not AlertManager.alert_active:
		target = null
		velocity.x = 0
		velocity.z = 0
		move_and_slide()
		return

	# After alert → normal combat logic
	target = _get_priority_target()

	if target != null:
		_attack_behavior()
	else:
		velocity.x = 0
		velocity.z = 0

	move_and_slide()

# ==============================
# ATTACK BEHAVIOR
# ==============================
func _attack_behavior():
	_rotate_to(target)

	var dist := global_position.distance_to(target.global_position)

	if dist <= shoot_range:
		velocity.x = 0
		velocity.z = 0
		if can_shoot:
			_shoot()
		return

	_move_direct(target.global_position, speed)
	
# ==============================
# MOVEMENT
# ==============================
func _move_direct(target_pos: Vector3, move_speed: float):
	var dir := target_pos - global_position
	dir.y = 0

	if dir.length() < 0.4:
		velocity.x = 0
		velocity.z = 0
		return

	dir = dir.normalized()

	# ✅ APPLY SEPARATION
	var separation :Vector3= _apply_separation()
	separation.y = 0

	# 🔑 combine movement + separation
	var final_dir := dir + separation * separation_strength

	# prevent zero-length direction
	if final_dir.length() < 0.05:
		final_dir = dir

	final_dir = final_dir.normalized()

	velocity.x = final_dir.x * move_speed
	velocity.z = final_dir.z * move_speed

# ==============================
# TARGET PRIORITY
# ==============================
func _get_priority_target() -> Node3D:
	# 1️⃣ Prefer players already close (Area3D)
	if nearby_players.size() > 0:
		return _get_nearest_from_array(nearby_players)

	# 2️⃣ Otherwise nearest player globally
	return _get_nearest_player()

func _get_nearest_from_array(arr: Array) -> Node3D:
	var nearest: Node3D = null
	var min_dist := INF

	for p in arr:
		if not is_instance_valid(p):
			continue
		var d := global_position.distance_to(p.global_position)
		if d < min_dist:
			min_dist = d
			nearest = p

	return nearest

func _get_nearest_player() -> Node3D:
	var nearest: Node3D = null
	var min_dist := INF

	for p in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(p):
			continue
		var d := global_position.distance_to(p.global_position)
		if d < min_dist:
			min_dist = d
			nearest = p

	return nearest

# ==============================
# AREA3D (PRIORITY ONLY)
# ==============================
func _on_Area3D_body_entered(body):
	if not AlertManager.alert_active:
		return
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

	remove_from_group("enemy")
	$CollisionShape3D.disabled = true
	queue_free()

# ==============================
# MATERIAL COLOR
# ==============================
func make_cop_dress():
	var bean = $mesh/bean
	_set_color(bean.get_node("Sphere"), Color(0.0, 0.1, 0.3))
	_set_color(bean.get_node("Sphere_003"), Color(0.0, 0.1, 0.3))
	_set_color(bean.get_node("Torus"), Color.BLACK)

func _set_color(mesh, color):
	if mesh == null or mesh.mesh == null:
		return
	for i in range(mesh.mesh.get_surface_count()):
		var mat = mesh.get_active_material(i)
		if mat:
			var new_mat = mat.duplicate()
			new_mat.albedo_color = color
			mesh.set_surface_override_material(i, new_mat)

func _apply_separation():
	var force := Vector3.ZERO

	for e in get_tree().get_nodes_in_group("enemy"):
		if e == self:
			continue
		if not is_instance_valid(e):
			continue

		var dist := global_position.distance_to(e.global_position)
		if dist > 0.0 and dist < separation_radius:
			var push :Vector3= global_position - e.global_position
			force += push.normalized() * (separation_radius - dist)

	return force
