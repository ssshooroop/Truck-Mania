extends SceneTree
const Scroller = preload("res://scripts/menu/road_scroller.gd")
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	root.size = Vector2i(540,1171)
	var road = Scroller.new()
	road.position = Vector2(0,180)
	road.size = Vector2(540,820)
	root.add_child(road)
	road.scroll = 0.0
	await process_frame
	await RenderingServer.frame_post_draw
	var a = root.get_texture().get_image()
	a.save_png("res://artifacts/road-stage1.png")
	road.scroll = 1.0
	await process_frame
	await RenderingServer.frame_post_draw
	var b = root.get_texture().get_image()
	assert(a.get_data() == b.get_data(),"Texture must repeat exactly")
	road.scroll = -1.0
	await process_frame
	await RenderingServer.frame_post_draw
	assert(a.get_data() == root.get_texture().get_image().get_data())
	print("Stage 1: positive and negative repeat pixel-identical; shader rendered.")
	quit()
