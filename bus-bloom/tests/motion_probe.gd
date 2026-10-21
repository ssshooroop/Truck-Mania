extends "res://scripts/main.gd"
## Executes the production arrival/loading/departure code, replacing only each
## tween with 61 geometric samples of the same interpolation and an instant end.

var motion_segments := 0
var motion_samples := 0
var pair_checks := 0
var collision_segments := 0
var collision_details: Array = []
var invisible_samples := 0

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
	for sample in range(121):
		var t := sample / 120.0
		var pose: Dictionary = _drive_pose(start,end,initial,target_angle,t)
		var point: Vector2 = pose.position
		var rotation: float = pose.angle
		var direction := Vector2(sin(rotation), -cos(rotation))
		point = EdgeRoute.position_for(point,rotation,size)
		var half := (Vector2(direction.y,-direction.x).abs()*size.x+direction.abs()*size.y)*0.5
		if not Rect2(point-half,half*2).intersects(Rect2(Vector2.ZERO,EdgeRoute.SCREEN)):
			invisible_samples += 1
		motion_samples += 1
		for other: Dictionary in model.buses:
			if other.id == id or other.status not in ["yard", "docked"]:
				continue
			var visual: Dictionary = bus_visuals[other.id]
			var other_rotation: float = visual.angle
			var other_direction := Vector2(sin(other_rotation), -cos(other_rotation))
			pair_checks += 1
			var other_position := EdgeRoute.position_for(visual.position,other_rotation,model.vehicle_size(other))
			if model._rectangles_overlap(point, direction, size, other_position, other_direction, model.vehicle_size(other)):
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

func _follow_route(id:int,path:Array) -> void:
	motion_segments+=1
	var moving:Dictionary=model.buses[id]
	var size:Vector2=model.vehicle_size(moving)
	var last:Dictionary=path[0]
	for pose:Dictionary in path:
		for sample in 3:
			var t:float=sample/3.0
			var point:Vector2=Vector2(last.position).lerp(pose.position,t)
			var angle:float=lerp_angle(last.angle,pose.angle,t)
			var direction:=Vector2(sin(angle),-cos(angle))
			var half:Vector2=(Vector2(direction.y,-direction.x).abs()*size.x+direction.abs()*size.y)*0.5
			if not Rect2(point-half,half*2).intersects(Rect2(Vector2.ZERO,EdgeRoute.SCREEN)): invisible_samples+=1
			motion_samples+=1
			for other:Dictionary in model.buses:
				if other.id==id or other.status not in ["yard","docked","leaving"]: continue
				var v:Dictionary=bus_visuals[other.id]
				pair_checks+=1
				if model._rectangles_overlap(point,direction,size,v.position,Vector2(sin(v.angle),-cos(v.angle)),model.vehicle_size(other)):
					collision_segments+=1
					print("CURVE_COLLISION level=",model.level_index+1," truck=",id," other=",other.id," status=",moving.status," step=",Vector2(last.position).distance_to(pose.position)," turn=",angle_difference(last.angle,pose.angle)," t=",t," p=",point)
		last=pose
	bus_visuals[id].position=path.back().position
	bus_visuals[id].angle=path.back().angle
	bus_visuals[id].route=true
	await get_tree().process_frame
