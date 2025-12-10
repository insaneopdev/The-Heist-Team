extends Area3D

# BULLET VARIABLES
@export var bullet_speed = 30.0
@export var life_time := 2.0

# BULLET EFFECTS
@onready var wall_impact = $wall_impact/mesh

# OTHER VARIABLES
var direction := Vector3.ZERO


func _ready():
	direction = -global_transform.basis.z.normalized()
	wall_impact.hide()


func _physics_process(delta):
	var start = global_transform.origin
	var end = start + direction * bullet_speed * delta

	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(start, end)
	query.collide_with_bodies = true
	query.collide_with_areas = true
	query.hit_back_faces = true

	var result = space_state.intersect_ray(query)

	if result:
		var hit_pos = result.position
		var hit_norm = result.normal

		wall_impact.show()
		wall_impact.global_transform.origin = hit_pos + hit_norm * 0.05

		var up_dir = Vector3.UP
		if abs(hit_norm.dot(Vector3.UP)) > 0.9:
			up_dir = Vector3.FORWARD

		wall_impact.look_at(hit_pos + hit_norm, up_dir)
		wall_impact.scale = Vector3(0.1, 0.1, 0.1)

		var impact = wall_impact.duplicate()
		impact.global_transform = wall_impact.global_transform
		get_tree().current_scene.add_child(impact)

		get_tree().create_timer(5.0).timeout.connect(impact.queue_free)

		queue_free()
		return

	global_transform.origin = end

	life_time -= delta
	if life_time <= 0:
		queue_free()
