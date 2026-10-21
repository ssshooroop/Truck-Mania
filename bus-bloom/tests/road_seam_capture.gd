extends SceneTree
const Road = preload("res://scripts/menu/road_scroller.gd")
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	root.size = Vector2i(540,1171)
	var road = Road.new()
	road.projection = load("res://scenes/menu/road_projection.tres")
	road.size = Vector2(540,1171)
	road.scroll = 0.0
	root.add_child(road)
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/road-seam.png")
	var error:float = 0.0
	for i in range(1,7):
		var a:float = road.projection._aligned_x(road.projection.SEAM_TOP[i]/1536.0,0.0)
		var b:float = road.projection._aligned_x(road.projection.SEAM_BOTTOM[i]/1536.0,1.0)
		error = maxf(error,absf(a-b)*1536.0)
	print("Seam boundary mismatch: ",error," pixels")
	quit(1 if error>0.01 else 0)
