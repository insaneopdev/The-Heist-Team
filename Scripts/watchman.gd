extends CharacterBody3D

# NODE RELATION 
@onready var detector = $pivot/RayCast3D

# SCENE 
@export var Bullet_Scene:PackedScene


func _ready() -> void:
	make_watchman_dress()  


func _physics_process(delta: float) -> void:
	pass


# -----------------------
# COP UNIFORM FUNCTION
# -----------------------
func make_watchman_dress() -> void:
	var bean = $mesh/bean

	_set_color(bean.get_node("Sphere"), Color(0.4, 0.6, 1.0))     # body light blue

	_set_color(bean.get_node("Sphere_003"), Color(0.05, 0.05, 0.1)) # hat top dark
	_set_color(bean.get_node("Torus"), Color(0, 0, 0))            # hat edge blac
	


# -----------------------
# HELPER FUNCTION
# -----------------------
func _set_color(mesh: MeshInstance3D, color: Color):
	if mesh == null or mesh.mesh == null:
		return

	for i in range(mesh.mesh.get_surface_count()):
		var mat = mesh.get_active_material(i)
		if mat:
			var new_mat = mat.duplicate()
			new_mat.albedo_color = color
			mesh.set_surface_override_material(i, new_mat)
