extends SceneTree
const Game = preload("res://scripts/main.gd")
var failures = 0
var checks = 0
func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	root.size = Vector2i(540,1171)
	var game = Game.new()
	root.add_child(game)
	game.save_enabled = false
	game.automation = true
	game.unlocked = 0
	game._show_road_menu(false)
	var menu = game.road_menu
	menu.configure(3,0,false,false)
	await process_frame
	check(menu.markers.size()==3,"Three-marker prototype")
	var area = Rect2(menu.road.position,menu.road.size)
	for world in [-1.02,-0.01,0.0,0.01,0.25,0.99,1.01]:
		var p:Vector3 = menu.projection.project(world,0,world-0.1,area)
		check(absf(menu.projection.world_at_y(p.y,area)-0.1)<0.00001,"Projection and drag inverse agree")
		check(absf(menu.projection.center_x(world)-menu.projection.center_x(world+1))<0.00001,"Centerline loops")
	var scenery_before = {}
	for prop in menu.decorations:
		if prop.enabled: scenery_before[prop.world] = [prop.kind,prop.lateral,prop.size_factor]
	var original_scroll:float = menu.road.scroll
	menu.road.scroll -= 2.0
	menu._process(0)
	menu.road.scroll = original_scroll
	menu._process(0)
	var scenery_after = {}
	for prop in menu.decorations:
		if prop.enabled:
			scenery_after[prop.world] = [prop.kind,prop.lateral,prop.size_factor]
			var half_width:float = prop.drawn_size().x*prop.size_factor/1080.0
			check(absf(prop.lateral)-half_width>=0.1299,"Large decorations leave the road clear")
	check(scenery_before==scenery_after,"Returning restores the same tree groups and offsets")
	for step in 48:
		menu.road.scroll = -step/16.0
		menu._process(0)
		for prop in menu.decorations:
			if not prop.enabled: continue
			var bounds:Vector2 = menu.projection.scenery_edges(prop.world)
			var x:float = menu.projection.center_x(prop.world)+prop.lateral
			var half:float = prop.drawn_size().x*prop.size_factor/1080.0
			check(x+half<=bounds.x-0.0199 or x-half>=bounds.y+0.0199,"Decoration clears measured road shoulders")
			check(x-half>=0.0199 and x+half<=0.9801,"Decoration fits grass")
	menu.road.scroll = original_scroll
	menu._process(0)

	var selected:Array = []
	var callback = func(index:int): selected.append(index)
	menu.level_selected.disconnect(game._load_level)
	menu.level_selected.connect(callback)
	var point:Vector2 = menu.markers[0].position
	menu._begin(point)
	menu._end(point)
	check(selected==[0],"Tap unlocked marker")
	selected.clear()
	point = menu.markers[1].position
	menu._begin(point)
	menu._end(point)
	check(selected.is_empty(),"Locked marker cannot launch")
	point = menu.markers[0].position
	menu._begin(point)
	menu._drag(point+Vector2(0,170))
	menu._end(point+Vector2(0,170))
	check(selected.is_empty(),"Drag does not launch a level")
	check(menu.road.velocity!=0,"Release preserves inertia")
	for i in 600: menu.road._process(1.0/60.0)
	var n = (menu.road.origin-menu.road.scroll)/menu.level_spacing
	check(absf(n-roundf(n))<0.001,"Inertia settles on a level")
	menu.configure(3,0,false,false)
	point = menu.markers[0].position
	var touch = InputEventScreenTouch.new()
	touch.index = 0
	touch.position = point
	touch.pressed = true
	menu._input(touch)
	touch.pressed = false
	menu._input(touch)
	check(selected==[0],"Touch selects the level exactly once")
	selected.clear()
	var mouse = InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = point
	mouse.pressed = true
	menu._input(mouse)
	mouse.pressed = false
	menu._input(mouse)
	check(selected==[0],"Mouse selects the level exactly once")
	for dimensions in [Vector2(390,844),Vector2(430,932),Vector2(768,1024)]:
		menu.size = dimensions
		menu._layout()
		menu._process(0)
		check(is_equal_approx(menu.road.get_rect().end.y,dimensions.y) and menu.road.size.x==dimensions.x,"Portrait layout fits viewport")
	menu.size = Vector2(540,1171)
	menu._layout()
	menu.level_selected.disconnect(callback)
	menu.level_selected.connect(game._load_level)
	game._show_road_menu(false)
	check(menu.markers.size()==game.model.level_count(),"Uses actual level count")
	game._open_settings()
	check(game.overlay=="settings" and menu.visible,"Settings open over the map")
	game._resume()
	check(game.overlay=="road_menu" and menu.visible,"Settings return to menu")
	menu.level_selected.emit(0)
	check(game.overlay=="" and not menu.visible,"Marker starts gameplay")
	var snapshot = game.model.snapshot()
	game._show_road_menu(true)
	game._resume_from_menu()
	check(game.model.snapshot()==snapshot and game.overlay=="","Return preserves gameplay")
	game._show_road_menu(false)
	if "--capture-menu" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/road-menu.png")
	print("Road menu: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
