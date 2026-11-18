extends SceneTree
const Loc = preload("res://scripts/localization.gd")
const Modal = preload("res://scripts/ui/game_modal.gd")
const Catalog = preload("res://scripts/ui/modal_catalog.gd")
const Menu = preload("res://scripts/ui/menu_windows.gd")
func _initialize(): run.call_deferred()
func run():
	Loc.initialize()
	root.content_scale_size=Vector2i(540,720)
	root.size=Vector2i(540,720)
	for locale in ["fr","ar","ja"]:
		Loc.set_locale(locale)
		for kind in ["crane","support"]:
			var spec=Catalog.crane_intro(100) if kind=="crane" else Menu.support("translations-20261024","TEST-ID")
			var modal=Modal.new(spec)
			modal.reduced_motion=true
			modal.age=1.0
			root.add_child(modal)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://artifacts/delta-%s-%s.png"%[locale,kind])
			modal.queue_free()
			await process_frame
	quit()
