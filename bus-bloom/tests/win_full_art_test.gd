extends SceneTree
const Modal=preload("res://scripts/ui/game_modal.gd")
const Catalog=preload("res://scripts/ui/modal_catalog.gd")
func _initialize():run.call_deferred()
func run():
	for height in [720,1171]:
		root.content_scale_size=Vector2i(540,height)
		root.size=Vector2i(540,height)
		for variant in ["standard","double","replay"]:
			var spec=Catalog.win({"reward":0 if variant=="replay" else 50,"before":100,"coins":100 if variant=="replay" else 150,"can_double":variant=="double","last":variant=="replay"})
			var m=Modal.new(spec)
			m.reduced_motion=true
			m.age=1.0
			root.add_child(m)
			await process_frame
			await RenderingServer.frame_post_draw
			for item in m.placed:
				if item.block.type=="art":
					assert(item.block.fit=="contain")
					var source:Vector2=item.block.texture.get_size()
					var fitted=Modal.contained_art_rect(source,item.rect)
					assert(item.rect.grow(0.001).encloses(fitted))
					assert(is_equal_approx(fitted.size.aspect(),source.aspect()))
			root.get_texture().get_image().save_png("res://artifacts/modals/win-full-%s-%d.png"%[variant,height])
			m.queue_free()
			await process_frame
	print("Full victory artwork: 3 states at phone and tablet sizes passed")
	quit()
