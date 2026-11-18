extends SceneTree
const Loc = preload("res://scripts/localization.gd")
const Modal = preload("res://scripts/ui/game_modal.gd")
const Catalog = preload("res://scripts/ui/modal_catalog.gd")
func _initialize(): run.call_deferred()
func run():
	Loc.initialize()
	root.content_scale_size=Vector2i(540,720)
	root.size=Vector2i(540,720)
	for locale in ["en","ja","ko","zh","ar"]:
		Loc.set_locale(locale)
		for kind in ["shortfall","win"]:
			var spec = Catalog.shortfall(100,20,25,true,{}) if kind=="shortfall" else Catalog.win({"reward":50,"before":100,"coins":150,"can_double":true})
			var modal = Modal.new(spec)
			modal.reduced_motion = true
			modal.age = 1.0
			root.add_child(modal)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://artifacts/localization-%s-%s.png"%[locale,kind])
			modal.queue_free()
			await process_frame
	print("Localization visual fixtures rendered")
	quit()
