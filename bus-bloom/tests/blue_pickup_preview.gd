extends SceneTree
## A visual review of the updated artwork using the production renderer.

class Preview extends Node2D:
	const Art = preload("res://scripts/cargo_art.gd")
	var elapsed := 10.0
	var reduced_motion := true
	var font: Font
	var art

	func _ready() -> void:
		font = ThemeDB.fallback_font
		art = Art.new(self,font)

	func label(value: String, position: Vector2, size: int) -> void:
		var width = font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
		draw_string(font,position-Vector2(width/2,0),value,HORIZONTAL_ALIGNMENT_LEFT,-1,size,Color.WHITE)

	func _draw() -> void:
		draw_rect(Rect2(0,0,840,510),Color("b2b0b6"))
		label("ОБНОВЛЁННЫЙ СИНИЙ ПИКАП",Vector2(420,44),25)
		label("Пустой кузов",Vector2(155,111),18)
		label("С грузом",Vector2(380,111),18)
		label("В игровом размере",Vector2(660,180),18)
		for loaded in 2:
			var truck = {"id":loaded,"kind":0,"color":4,"capacity":2,"load":2 if loaded else 0,"status":"docked" if loaded else "yard"}
			art.vehicle(truck,Vector2(155+loaded*225,302),0.0,3.0)
			truck.id = loaded+2
			art.vehicle(truck,Vector2(615+loaded*92,285),0.0,1.0)
		label("Твой цвет без автоматической перекраски",Vector2(420,482),17)

var canvas: SubViewport

func _initialize() -> void:
	canvas = SubViewport.new()
	canvas.size = Vector2i(840,510)
	canvas.disable_3d = true
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child.call_deferred(canvas)
	canvas.add_child.call_deferred(Preview.new())
	_capture.call_deferred()

func _capture() -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var result = canvas.get_texture().get_image().save_png("res://artifacts/blue-pickup-preview.png")
	print("BLUE_PICKUP_PREVIEW_SAVED result=",result)
	quit(0 if result==OK else 1)
