extends Control

func _draw():
	var center = size * 0.5
	draw_circle(center, 5, Color.RED)

func _process(_delta):
	queue_redraw()
