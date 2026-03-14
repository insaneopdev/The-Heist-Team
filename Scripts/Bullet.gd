extends Area3D

@export var bullet_speed = 60.0
@export var life_time := 2.0

var direction: Vector3 = Vector3.ZERO
var damage: int = 10
var shooter_id: int = 0 

func _ready():
	if direction != Vector3.ZERO:
		var up_vec = Vector3.UP
		if abs(direction.normalized().dot(Vector3.UP)) > 0.999:
			up_vec = Vector3.RIGHT
		look_at(global_position + direction, up_vec)

func _physics_process(delta):
	var start = global_transform.origin
	var end = start + direction * bullet_speed * delta

	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(start, end)
	query.collide_with_bodies = true
	query.collide_with_areas = true
	query.exclude = [self] 

	var result = space_state.intersect_ray(query)

	if result:
		var hit_obj = result.collider
		
		# Only the person who fired calculates the hit
		if shooter_id == multiplayer.get_unique_id():
			
			# 1. IGNORE FRIENDLY FIRE (Other Players)
			if hit_obj.is_in_group("player"):
				# Do nothing, just destroy bullet
				pass
				
			# 2. DAMAGE COPS
			if hit_obj.is_in_group("enemy"):
				if hit_obj.has_method("receive_damage"):
					hit_obj.rpc("receive_damage", damage, shooter_id)
		
		queue_free()
		return

	global_transform.origin = end
	life_time -= delta
	if life_time <= 0:
		queue_free()
