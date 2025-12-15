extends CharacterBody3D

# ==============================
# NODE REFERENCES
# ==============================
@onready var pivot       = $pivot
@onready var primary_gun = $pivot/primary_gun
@onready var p_muzzle    = $pivot/primary_gun/gun_muzzle
@onready var vision_area = $pivot/Area3D

# ==============================
# EXPORTS
# ==============================
@export var Bullet_Scene: PackedScene
@export var speed := 5.0
@export var shoot_range := 12.0
@export var shoot_delay := 0.6
@export var gravity := 20.0

# ==============================
# STATE
# ==============================
var detected := false
var target: Node3D = null
var can_shoot := true
var health := 100

# ==============================
# SEARCH
# ==============================
var last_player_pos := Vector3.ZERO
var searching_lost_player := false
var search_timer := 0.0
var max_search_time := 2.0
var chase_speed_multiplier := 1.35
var search_arrival_dist := 1.0

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

# ==============================
# PHYSICS LOOP
# ==============================
func _physics_process(delta):
	# 🔒 SERVER-ONLY AI
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	if detected:
		_detected_behavior()
	elif searching_lost_player:
		_search_behavior(delta)
	else:
		_idle_behavior()

	_apply_gravity(delta)
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
	if target == null:
		return

	last_player_pos = target.global_position
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
# SEARCH
# ==============================
func _search_behavior(delta):
	search_timer += delta
	_move_direct(last_player_pos, speed * chase_speed_multiplier)

	if global_position.distance_to(last_player_pos) <= search_arrival_dist:
		velocity = Vector3.ZERO
		if search_timer >= max_search_time:
			searching_lost_player = false

# ==============================
# MOVEMENT
# ==============================
func _move_direct(target_pos: Vector3, move_speed: float):
	var dir := target_pos - global_position
	dir.y = 0

	if dir.length() < 0.5:
		velocity = Vector3.ZERO
		return

	dir = dir.normalized()
	velocity.x = dir.x * move_speed
	velocity.z = dir.z * move_speed

# ==============================
# TARGET SELECTION
# ==============================
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
# AREA3D DETECTION (WATCHMAN)
# ==============================
func _on_Area3D_body_entered(body):
	if not body.is_in_group("player"):
		return
	

	# 🔒 ALERT MUST BE SERVER-SIDE
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	if not AlertManager.alert_active:
		AlertManager.raise_alert(body.global_position)

	target = body
	detected = true
	searching_lost_player = false
	search_timer = 0.0
	last_player_pos = body.global_position

func _on_Area3D_body_exited(body):
	if body != target:
		return

	detected = false
	target = null
	searching_lost_player = true
	search_timer = 0.0

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
# VISUALS
# ==============================
func make_watchman_dress():
	var bean = $mesh/bean
	_set_color(bean.get_node("Sphere"), Color(0.4, 0.6, 1.0))
	_set_color(bean.get_node("Sphere_003"), Color(0.05, 0.05, 0.1))
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
