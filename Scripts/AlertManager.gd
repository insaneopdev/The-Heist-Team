extends Node

var alert_active := false
var alert_position := Vector3.ZERO

func raise_alert(pos: Vector3):
	if alert_active:
		return
	alert_active = true
	alert_position = pos
