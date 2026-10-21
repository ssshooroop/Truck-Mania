extends SceneTree
const Model=preload("res://scripts/game_model.gd")
func _initialize():
	var original=Model.new()
	var tablet=Model.new()
	tablet.tablet_layout=true
	var failures:=0
	for level in original.level_count():
		original.load_level(level)
		tablet.load_level(level)
		for b in tablet.buses:
			if tablet.blocking_ids(b.id)!=original.blocking_ids(b.id): failures+=1
			if tablet.maneuver_paths(b.id).is_empty()!=original.maneuver_paths(b.id).is_empty(): failures+=1
			var size:Vector2=tablet.vehicle_size(b)
			for x in [-size.x/2,size.x/2]:
				for y in [-size.y/2,size.y/2]:
					if not Rect2(44,389,452,237).has_point(b.position+Vector2(x,y).rotated(b.angle)):failures+=1
		if not tablet.restore(tablet.undo_snapshot()):failures+=1
		print("Tablet level ",level+1," scale=",tablet.layout_scale," rotation=",rad_to_deg(tablet.layout_transform.get_rotation()))
	print("Tablet layout failures: ",failures)
	quit(1 if failures else 0)
