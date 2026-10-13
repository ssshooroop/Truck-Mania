extends SceneTree
## Render the actual game artwork at its game size for reviewing empty and loaded beds.

class Gallery extends Node2D:
	const Art = preload("res://scripts/cargo_art.gd")
	var elapsed := 10.0
	var reduced_motion := true
	var font: Font
	var art
	func _ready() -> void:
		font = ThemeDB.fallback_font
		art = Art.new(self,font)
	func _draw() -> void:
		draw_rect(Rect2(0,0,1200,1000),Color("f3f6fc"))
		draw_string(font,Vector2(28,44),"ВАШИ МАШИНКИ В ИГРЕ",HORIZONTAL_ALIGNMENT_LEFT,-1,28,Color("152b46"))
		draw_string(font,Vector2(28,72),"В каждой паре: пустая машина и полностью загруженная",HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("536780"))
		for material_id in 6:
			var center := 100.0+material_id*200
			var name_size: Vector2 = font.get_string_size(Art.NAMES[material_id],HORIZONTAL_ALIGNMENT_LEFT,-1,18)
			draw_string(font,Vector2(center-name_size.x/2,116),Art.NAMES[material_id],HORIZONTAL_ALIGNMENT_LEFT,-1,18,Art.COLORS[material_id].darkened(0.28))
		for kind in 3:
			var y := 242.0+kind*290
			draw_string(font,Vector2(28,y-104),"%s · %d" % [Art.TYPE_NAMES[kind],[2,4,6][kind]],HORIZONTAL_ALIGNMENT_LEFT,-1,19,Color("152b46"))
			for material_id in 6:
				var x := 100.0+material_id*200
				draw_rect(Rect2(x-84,y-99,168,211),Color("e1e9f5"))
				for loaded in 2:
					var truck := {"id":kind*100+material_id*2+loaded,"kind":kind,"color":material_id,"capacity":[2,4,6][kind],"load":[2,4,6][kind] if loaded else 0,"status":"docked" if loaded else "yard"}
					art.vehicle(truck,Vector2(x+(-42 if loaded==0 else 42),y+7),0.0,1.0)
					if loaded: draw_string(font,Vector2(x+22,y+122),"%d / %d" % [truck.capacity,truck.capacity],HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("152b46"))

var gallery_view: SubViewport

func _initialize() -> void:
	gallery_view = SubViewport.new()
	gallery_view.size = Vector2i(1200,1000)
	gallery_view.disable_3d = true
	gallery_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child.call_deferred(gallery_view)
	gallery_view.add_child.call_deferred(Gallery.new())
	_capture.call_deferred()

func _capture() -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var result := gallery_view.get_texture().get_image().save_png("res://artifacts/factory-trucks-sheet.png")
	print("VEHICLE_GALLERY_SAVED result=",result)
	quit(0 if result==OK else 1)
