extends Area3D

#BULLET SETTINGS
@export var bullet_speed = 30.0
@export var life_time := 2.0

#OTHER VARIABLES
var direction: Vector3 = Vector3.ZERO
var shooter    


func _physics_process(delta):
	var start = global_transform.origin
	var end = start + direction * bullet_speed * delta

	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(start, end)
	query.collide_with_bodies = true
	query.collide_with_areas = true
	query.hit_back_faces = true

	var ignore_list = [self]
	if shooter:
		ignore_list.append(shooter)
	query.exclude = ignore_list

	var result = space_state.intersect_ray(query)

	if result:
		
		queue_free()
		return

	# move bullet
	global_transform.origin = end

	life_time -= delta
	if life_time <= 0:
		queue_free()
