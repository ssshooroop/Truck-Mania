extends SceneTree
func _initialize(): run.call_deferred()
func run():
	var game=preload("res://scripts/main.gd").new()
	game.automation=true
	root.add_child(game)
	game._show_road_menu(false)
	game.save_path="user://daily-modal-test.cfg"
	game.save_enabled=true
	game.daily_rewards=preload("res://scripts/daily_rewards.gd").new()
	var before:int=game.coins
	root.size=Vector2i(540,720)
	game._open_daily_bonus(true)
	assert(game.modal.spec.id=="daily" and game.coins==before)
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/daily-available.png")
	game._close_modal(true)
	game._open_daily_bonus(true)
	assert(game.coins==before)
	game._on_daily_action("claim")
	assert(game.coins==before+20)
	game._on_daily_action("claim")
	assert(game.coins==before+20)
	await create_timer(1.8).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/daily-claimed.png")
	game._close_modal(true)
	game._open_daily_bonus(true)
	assert(not game.modal.spec.get("fly",false))
	for b in game.modal.spec.blocks: assert(b.get("id","")!="claim")
	game.save_enabled=false
	game.queue_free()
	await process_frame
	print("Daily modal: claim on button, close/reopen, idempotency and claimed view passed")
	quit()
