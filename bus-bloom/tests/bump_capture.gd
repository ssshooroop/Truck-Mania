extends SceneTree
const Game = preload("res://scripts/main.gd")
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	root.size = Vector2i(540,1171)
	var game = Game.new()
	root.add_child(game)
	game.automation = true
	game.save_enabled = false
	game.sound_enabled = false
	game._load_level(0)
	for bus:Dictionary in game.model.buses:
		if game.model.blocking_ids(bus.id).is_empty(): continue
		game._dispatch(bus.id)
		while game.impact.is_empty(): await process_frame
		if game.motion_tween: game.motion_tween.pause()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/blocked-contact.png")
		game._cancel_animation()
		break
	quit()
