extends Area3D

#BULLET SETTINGS
@export var bullet_speed = 30.0
@export var life_time := 2.0
@export var impact_scene: PackedScene

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
		var hit_pos = result.position
		var hit_norm = result.normal

		var impact = impact_scene.instantiate()
		get_tree().current_scene.add_child(impact)

		impact.global_position = hit_pos + hit_norm * 0.05

		var up_dir = Vector3.UP
		if abs(hit_norm.dot(Vector3.UP)) > 0.9:
			up_dir = Vector3.FORWARD

		impact.look_at(hit_pos + hit_norm, up_dir)
		impact.scale = Vector3(0.1, 0.1, 0.1)

		get_tree().create_timer(0.1).timeout.connect(impact.queue_free)
		queue_free()
		return

	# move bullet
	global_transform.origin = end

	life_time -= delta
	if life_time <= 0:
		queue_free()
