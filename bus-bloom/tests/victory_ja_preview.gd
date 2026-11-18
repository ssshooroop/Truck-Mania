extends SceneTree
func _initialize():run.call_deferred()
func run():
	var l=preload("res://scripts/localization.gd");l.initialize();l.set_locale("ja")
	root.size=Vector2i(540,900)
	var spec=preload("res://scripts/ui/modal_catalog.gd").win({"reward":50,"before":413,"coins":463,"can_double":true,"details":{"base":25,"streak":25}})
	var modal=preload("res://scripts/ui/game_modal.gd").new(spec);root.add_child(modal)
	await create_timer(0.6).timeout;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/victory-ja-fixed.png")
	quit()
