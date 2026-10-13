extends "res://scripts/main.gd"
## Executes the production arrival/loading/departure code, replacing only each
## tween with 61 geometric samples of the same interpolation and an instant end.

var motion_segments := 0
var motion_samples := 0
var pair_checks := 0
var collision_segments := 0
var collision_details: Array = []

func _ready() -> void:
	save_enabled = false
	automation = true
	sound_enabled = false
	speed_factor = 0.0001
	Engine.max_fps = 1000
	_load_level(0)

func _process(_delta: float) -> void:
	pass

func _draw() -> void:
	pass

func _play(_key: String) -> void:
	pass

func _walk(end: Vector2, _seconds: float) -> void:
	worker_position = end
	await get_tree().process_frame

func _drive(id: int, end: Vector2, _seconds: float, angle: float = INF) -> void:
	var start: Vector2 = bus_visuals[id].position
	var initial: float = bus_visuals[id].angle
	var delta := end - start
	var target_angle := angle if is_finite(angle) else atan2(delta.x, -delta.y)
	var moving: Dictionary = model.get_bus(id)
	var size: Vector2 = model.vehicle_size(moving)
	var hit_ids: Array = []
	motion_segments += 1
	for sample in range(122):
		var t := (sample % 61) / 60.0
		var point := start if sample < 61 else start.lerp(end, t)
		var rotation := lerp_angle(initial, target_angle,t) if sample < 61 else target_angle
		var direction := Vector2(sin(rotation), -cos(rotation))
		motion_samples += 1
		for other: Dictionary in model.buses:
			if other.id == id or other.status not in ["yard", "docked"]:
				continue
			var visual: Dictionary = bus_visuals[other.id]
			var other_rotation: float = visual.angle
			var other_direction := Vector2(sin(other_rotation), -cos(other_rotation))
			pair_checks += 1
			if model._rectangles_overlap(point, direction, size, visual.position, other_direction, model.vehicle_size(other)):
				if not hit_ids.has(other.id):
					hit_ids.append(other.id)
					var detail := "level=%d moving=%d other=%d (%s) sample_t=%.4f center=%s angle=%.3f segment=%s -> %s initial=%.3f target=%.3f" % [model.level_index + 1, id, other.id, other.status, t, point, rotation, start, end, initial, target_angle]
					collision_details.append(detail)
					print("MOTION_COLLISION " + detail)
	if not hit_ids.is_empty():
		collision_segments += 1
	bus_visuals[id].position = end
	bus_visuals[id].angle = target_angle
	await get_tree().process_frame
