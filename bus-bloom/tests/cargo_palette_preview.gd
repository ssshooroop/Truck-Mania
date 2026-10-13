extends SceneTree
## Render the three adjusted materials and their trucks on the actual asphalt.

class Gallery extends Node2D:
	const Art = preload("res://scripts/cargo_art.gd")
	const MATERIALS = [1,5,2]
	const INK = Color("23303d")
	var elapsed := 10.0
	var reduced_motion := true
	var font: Font
	var art

	func _ready() -> void:
		font = ThemeDB.fallback_font
		art = Art.new(self,font)

	func _label(text: String, center: Vector2, size: int, tint: Color = INK) -> void:
		var width: float = font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
		draw_string(font,Vector2(center.x-width*0.5,center.y),text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,tint)

	func _draw() -> void:
		draw_rect(Rect2(0,0,960,620),Color("b2b0b6"))
		_label("Цвета грузов и машин",Vector2(480,42),28)
		for column in 3:
			var material_id: int = MATERIALS[column]
			var center := 160.0+column*320.0
			_label(Art.NAMES[material_id],Vector2(center,96),24)
			art.material(Vector2(center,174),material_id,3.0)
			_label("Пустая",Vector2(center-65,259),16)
			_label("С грузом",Vector2(center+65,259),16)
			for loaded in 2:
				var truck := {
					"id":column*2+loaded,"kind":1,"color":material_id,
					"capacity":4,"load":4 if loaded else 0,
					"status":"docked" if loaded else "yard"
				}
				art.vehicle(truck,Vector2(center+(-65.0 if loaded==0 else 65.0),377),0.0,1.4)
			_label("Груз в игровом размере",Vector2(center,534),16)
			for unit in 3:
				art.material(Vector2(center+(unit-1)*36.0,574),material_id,1.0)

var gallery_view: SubViewport

func _initialize() -> void:
	gallery_view = SubViewport.new()
	gallery_view.size = Vector2i(960,620)
	gallery_view.disable_3d = true
	gallery_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child.call_deferred(gallery_view)
	gallery_view.add_child.call_deferred(Gallery.new())
	_capture.call_deferred()

func _capture() -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var result := gallery_view.get_texture().get_image().save_png("res://artifacts/cargo-colors-preview.png")
	print("CARGO_PALETTE_PREVIEW_SAVED result=",result)
	quit(0 if result==OK else 1)
