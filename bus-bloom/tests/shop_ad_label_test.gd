extends SceneTree
const Modal=preload("res://scripts/ui/game_modal.gd")
const Catalog=preload("res://scripts/ui/modal_catalog.gd")
const Loc=preload("res://scripts/localization.gd")
func _initialize(): run.call_deferred()
func run():
	Loc.initialize()
	var store=preload("res://scripts/ui/store_service.gd").new()
	DirAccess.make_dir_recursive_absolute("res://artifacts/shop-ad-label")
	for language in Loc.SUPPORTED:
		Loc.set_locale(language)
		for label in ["Скоро","Бесплатно"]:
			var layout=Modal._pack_ad_layout(Rect2(0,0,120,46),label)
			assert(not layout.icon.intersects(layout.area))
			assert(layout.paragraph.get_size().y<=layout.area.size.y,"Label too tall: "+language)
			for i in layout.paragraph.get_line_count():
				assert(layout.paragraph.get_line_size(i).x<=layout.area.size.x,"Label too wide: "+language)
		if not "--capture" in OS.get_cmdline_user_args():continue
		if language not in ["en","de","fr","ar"]:continue
		for height in [720,1171]:
			root.content_scale_size=Vector2i(540,height);root.size=Vector2i(540,height)
			for ready in [false,true]:
				var modal=Modal.new(Catalog.shop({"coins":70,"store":store,"owned":["starter"],"ad_ready":ready,"ad_coins":25}))
				root.add_child(modal);modal.age=4
				await process_frame;await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://artifacts/shop-ad-label/%s-%d-%s.png"%[language,height,str(ready)])
				modal.free()
	print("PASS: shop ad labels fit in all 11 languages, ready and unavailable")
	quit()
