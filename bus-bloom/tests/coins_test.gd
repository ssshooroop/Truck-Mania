extends SceneTree
const Game = preload("res://scripts/main.gd")
var checks = 0
var failures = 0
func check(ok:bool,message:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	_run.call_deferred()
func finish_level(game) -> void:
	game.model.queue.clear()
	for bus in game.model.buses: bus.status = "gone"
	game._check_end()
func _run() -> void:
	root.size = Vector2i(540,1171)
	var game = Game.new()
	root.add_child(game)
	game.automation = true
	game._sync_audio_preferences()
	game.reduced_motion = true
	game.save_path = "res://artifacts/coins-test.cfg"
	game.save_enabled = true
	# Legacy progress without a wallet receives the configured initial balance.
	game.economy = preload("res://scripts/runtime_economy.gd").new()
	var old := ConfigFile.new()
	old.set_value("game","unlocked",2)
	old.set_value("settings","sound",false)
	old.save(game.save_path)
	game._load_save()
	check(game.coins==50 and game.rewarded_levels.is_empty() and game.unlocked==2,"Legacy save retains progress and receives initial balance")
	game._load_level(0)
	game._check_end()
	check(game.coins==50,"Unfinished level earns nothing")
	finish_level(game)
	check(game.coins==76 and game.level_reward==26,"First victory awards base plus clean streak")
	game._check_end()
	check(game.coins==76 and game.level_reward==26,"Repeated victory callback is idempotent")
	game._load_level(0)
	finish_level(game)
	check(game.coins==76 and game.level_reward==0,"Replaying a completed level earns nothing")
	game.coins = 0
	game.rewarded_levels.clear()
	game._load_save()
	check(game.coins==76 and 0 in game.rewarded_levels and not game.sound_enabled,"Balance, claims and settings survive reload")
	game._load_level(0)
	finish_level(game)
	check(game.coins==76,"Reload cannot repeat a reward")
	game._load_level(1)
	finish_level(game)
	check(game.coins==108 and game.level_reward==32,"Different level adds its own reward")
	check(game.coin_badge.amount==108 and game.road_menu.coin_badge.amount==108,"Both screens show current balance")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/coins-win.png")
	game._show_road_menu(false)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/coins-menu.png")
	game.save_enabled = false
	DirAccess.remove_absolute(game.save_path)
	game.free()
	await create_timer(0.35).timeout
	print("Coins: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
