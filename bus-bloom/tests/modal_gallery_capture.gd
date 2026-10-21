extends SceneTree
## Renders every modal over a live level and saves PNGs to artifacts/modals.
## Usage: godot --path bus-bloom --script res://tests/modal_gallery_capture.gd [-- --height=1171]
const Modal := preload("res://scripts/ui/game_modal.gd")
const Catalog := preload("res://scripts/ui/modal_catalog.gd")
func _initialize(): run.call_deferred()
func run():
	var height := 1171
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--height="): height = int(a.get_slice("=",1))
	root.content_scale_size=Vector2i(540,height)
	root.size=Vector2i(540,height)
	var game=preload("res://scripts/main.gd").new()
	game.save_enabled=false
	game.automation=true
	root.add_child(game)
	game._load_level(3)
	game.intro_delays.clear()
	var now := int(Time.get_unix_time_from_datetime_string("2026-10-21T12:00:00"))
	var event: Dictionary = Catalog.active_event(Catalog.load_events(),now)
	var truck: Vector2 = game._world_transform()*game.model.buses[game.model.find_hint()].position
	game.coin_badge.visible=false
	var specs := {
		"tutorial-1":Catalog.tutorial(0,{"center":truck,"radius":78.0}),
		"tutorial-3":Catalog.tutorial(2),
		"stuck-slot":Catalog.stuck({"coins":120,"slot_available":true,"slot_price":100,"ad_ready":true,"undo_price":20,"can_undo":true,"can_shuffle":true,"shuffle_price":30}),
		"stuck-crane":Catalog.stuck({"coins":40,"slot_available":false,"can_crane":true,"crane_price":150,"undo_gifts":2,"can_undo":true,"can_shuffle":false}),
		"stuck-no-help":Catalog.stuck({"coins":5,"rescue_left":false,"can_undo":false}),
		"offer-cone":Catalog.offer("extra_slot",100,120,true),
		"shortfall":Catalog.shortfall(150,40,25,true,{"coins":500,"price":"199 ₽"}),
		"shortfall-no-ad":Catalog.shortfall(150,40,25,false),
		"ad-offer":Catalog.ad_reward("offer",25,40),
		"ad-loading":Catalog.ad_reward("loading",25,40),
		"ad-failed":Catalog.ad_reward("failed",25,40),
		"ad-done":Catalog.ad_reward("done",25,65),
		"double":Catalog.double_reward(32,120,true),
		"seasonal":Catalog.seasonal(event,now),
	}
	var layer := CanvasLayer.new()
	layer.layer = 10
	root.add_child(layer)
	for key in specs:
		var m = Modal.new(specs[key])
		layer.add_child(m)
		m.age = 2.0
		if key=="ad-failed": m.flash("Ролик не загрузился")
		game.coin_badge.visible=false
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/modals/%s-%d.png" % [key,height])
		m.free()
	print("MODAL_GALLERY_SAVED %d" % specs.size())
	quit()
