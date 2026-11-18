extends SceneTree
const Main = preload("res://scripts/main.gd")
func _initialize(): run.call_deferred()
func run():
	var game = Main.new()
	game.automation = true
	root.add_child(game)
	root.size = Vector2i(540,720)
	game._show_road_menu(false)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/menu-new.png")
	game._set_preference("reduced_motion",true)
	assert(game.reduced_motion and not game.road_menu.motion_button.button_pressed)
	game._open_languages()
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	assert(game.modal.hits.has("language:ar"))
	root.get_texture().get_image().save_png("res://artifacts/menu-language.png")
	game.modal.action.emit("language:en")
	assert(preload("res://scripts/localization.gd").locale=="en")
	game._close_modal(true)
	game._open_support()
	await create_timer(0.4).timeout
	assert(game.modal.message_input!=null)
	game.modal.action.emit("send")
	assert(not game.modal.flash_text.is_empty())
	game.modal.message_input.text="Test message"
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/menu-support.png")
	game._close_modal(true)
	game.save_path="user://menu-test.cfg"
	game.save_enabled=true
	game._open_daily_bonus(true)
	assert(game.modal!=null)
	game._close_modal(true)
	game._open_daily_bonus(true)
	assert(game.modal!=null)
	game.save_enabled=false
	game.queue_free()
	await process_frame
	print("Menu: language, reduced motion, support and repeat daily calendar passed")
	quit()
