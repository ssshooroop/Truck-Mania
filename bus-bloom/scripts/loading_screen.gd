extends Control
## Lightweight first scene: show artwork before loading the game's resources.
const BACKGROUND = preload("res://assets/artwork/load screen/Load_screen.png")
const LOGO = preload("res://assets/artwork/load screen/Truck-Mania-Logo.png")
const GAME_PATH = "res://main.tscn"
var progress := 0.0
var automation := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)
	_start.call_deferred()

func _draw() -> void:
	var factor := maxf(size.x/BACKGROUND.get_width(),size.y/BACKGROUND.get_height())
	var drawn := BACKGROUND.get_size()*factor
	draw_texture_rect(BACKGROUND,Rect2((size-drawn)*0.5,drawn),false)
	var logo_width := minf(size.x*0.86,size.y*0.47)
	var logo_size := LOGO.get_size()*(logo_width/LOGO.get_width())
	var top := size.y*0.035
	if OS.has_feature("android") or OS.has_feature("ios"):
		var safe := DisplayServer.get_display_safe_area()
		top = maxf(top,(get_screen_transform().affine_inverse()*Vector2(safe.position)).y+8.0)
	draw_texture_rect(LOGO,Rect2(Vector2((size.x-logo_width)/2,top),logo_size),false)
	var width := size.x*0.76
	var bar := Rect2((size.x-width)/2,size.y*0.93,width,18)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("142c48")
	style.border_color = Color("fff2b0")
	style.set_border_width_all(2)
	style.set_corner_radius_all(9)
	draw_style_box(style,bar)
	if progress>0.0:
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color("ffc52d")
		fill.set_corner_radius_all(6)
		draw_style_box(fill,Rect2(bar.position+Vector2(4,4),Vector2((width-8)*progress,10)))

func _start() -> void:
	# Guarantee the background has actually been presented before costly setup.
	await RenderingServer.frame_post_draw
	var error := ResourceLoader.load_threaded_request(GAME_PATH)
	if error!=OK:
		push_error("Unable to request game scene: %s" % error)
		return
	var amount:Array = []
	while true:
		var status := ResourceLoader.load_threaded_get_status(GAME_PATH,amount)
		if status==ResourceLoader.THREAD_LOAD_LOADED: break
		if status==ResourceLoader.THREAD_LOAD_FAILED or status==ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			push_error("Unable to load game scene")
			return
		progress = float(amount[0])*0.85 if not amount.is_empty() else 0.0
		queue_redraw()
		await get_tree().process_frame
	progress = 0.9
	queue_redraw()
	await RenderingServer.frame_post_draw
	var packed:PackedScene = ResourceLoader.load_threaded_get(GAME_PATH)
	var game := packed.instantiate()
	game.automation = automation
	# Keep the loading artwork above the game's first frame and daily dialog.
	var cover := CanvasLayer.new()
	cover.layer = 100
	get_tree().root.add_child(cover)
	reparent(cover)
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	progress = 1.0
	queue_redraw()
	await RenderingServer.frame_post_draw
	var fade := create_tween()
	fade.tween_property(self,"modulate:a",0.0,0.2)
	await fade.finished
	cover.queue_free()

