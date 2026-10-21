extends SceneTree
const Game = preload("res://scripts/main.gd")
const Win = preload("res://scripts/win_celebration.gd")
var checks := 0
var failures := 0
func check(value:bool,label:String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	root.size = Vector2i(540,1171)
	var game = Game.new()
	game.save_path = "user://win-celebration-test.cfg"
	root.add_child(game)
	game.automation = true
	game.save_enabled = true
	game._sync_audio_preferences()
	game.set_process(false)
	game._load_level(0)
	game.rewarded_levels.clear()
	game.coins = 120
	game.reduced_motion = false
	game.model.queue.clear()
	for bus: Dictionary in game.model.buses: bus.status = "gone"
	game._check_end()
	var target: int = game.coins
	check(game.level_reward>0 and target==120+game.level_reward,"Wallet credited once before animation")
	check(game.coin_badge.amount==120,"Counter begins at previous balance")
	game._check_end()
	check(game.coins==target,"Repeated end check cannot duplicate coins")
	var saved := ConfigFile.new()
	saved.load(game.save_path)
	check(saved.get_value("economy","coins")==target,"Full reward saved before animation finishes")
	var previous := 120
	for i in range(241):
		var amount := Win.displayed_balance(120,target,i/100.0,false)
		check(amount>=previous and amount<=target,"Counter monotonically approaches balance")
		previous = amount
	check(previous==target,"Counter reaches exact wallet value")
	check(Win.displayed_balance(120,target,0,true)==target,"Reduced motion credits display immediately")
	var destination: Vector2 = game.coin_badge.position+Vector2(24,22)
	for i in Win.PARTICLES:
		var start: float = 0.50+i*0.065
		var duration: float = 0.68+i*0.018
		var first: Dictionary = Win.flight(i,start,destination)
		var last: Dictionary = Win.flight(i,start+duration-0.00001,destination)
		check(first.position.distance_to(Win.ORIGIN)<20,"Duplicate begins at reward coin")
		check(last.position.distance_to(destination)<0.1 and last.size<first.size,"Coin shrinks into badge")
		check(Win.flight(i,start+duration+0.01,destination).is_empty(),"Arrived coin disappears")
	for age in [0.22,1.12,2.5]:
		game.win_age = age
		game._process(0)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/win-celebration-%d.png" % roundi(age*100))
	check(game.coin_badge.visible and game.coin_badge.amount==target,"Badge remains visible on results")
	game.win_age = 0.3
	game._process(0)
	game._overlay_input(Win.NEXT.get_center())
	check(game.model.level_index==1 and game.coins==target and game.coin_badge.amount==target,"Early Next preserves reward and settles displayed balance")
	game._load_level(0)
	game.model.queue.clear()
	for bus: Dictionary in game.model.buses: bus.status = "gone"
	game._check_end()
	check(game.level_reward==0 and game.coins==target,"Replay has no new coin award")
	game._overlay_input(Win.REPLAY.get_center())
	check(game.overlay=="" and game.model.level_index==0,"Replay button restarts level")
	game.save_enabled = false
	game._cancel_animation()
	game.free()
	DirAccess.remove_absolute("user://win-celebration-test.cfg")
	await create_timer(0.35).timeout
	print("Win celebration: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
