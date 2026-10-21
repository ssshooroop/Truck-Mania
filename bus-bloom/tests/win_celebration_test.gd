extends SceneTree
## Level-complete window: wallet credited once and saved before the animation,
## counter climbs with the flying coins, Next / Replay / doubling by video.
const Game = preload("res://scripts/main.gd")
const Modal = preload("res://scripts/ui/game_modal.gd")
var checks := 0
var failures := 0
func check(value:bool,label:String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	_run.call_deferred()
func finish(game) -> void:
	game.model.queue.clear()
	for bus: Dictionary in game.model.buses: bus.status = "gone"
	game._check_end()
func _run() -> void:
	root.size = Vector2i(540,1171)
	var game = Game.new()
	game.save_path = "user://win-celebration-test.cfg"
	game.automation = true
	root.add_child(game)
	game.save_enabled = true
	game._load_level(0)
	game.rewarded_levels.clear()
	game.coins = 120
	game.reduced_motion = false
	finish(game)
	var target: int = game.coins
	check(game.level_reward>0 and target==120+game.level_reward,"Wallet credited once before animation")
	game._check_end()
	check(game.coins==target,"Repeated end check cannot duplicate coins")
	var saved := ConfigFile.new()
	saved.load(game.save_path)
	check(saved.get_value("economy","coins")==target,"Full reward saved before animation finishes")
	await process_frame
	await process_frame
	check(game._modal_is("win"),"Win window opens")
	check(game.modal.hits.has("double"),"First level offers doubling even before an ad is ready")
	game.ads.simulate = false
	game.modal.tap("double")
	check(game.coins==target and not game.reward_doubled,"Unavailable ad does not credit a reward or consume the offer")
	check(int(game.modal.spec.balance_from)==120 and int(game.modal.spec.balance)==target,"Counter animates from the old balance")
	check(not game.coin_badge.visible,"The window shows the balance instead of the game badge")
	var previous := 120
	for i in range(301):
		var amount := Modal.displayed_balance(120,target,i/100.0,false)
		check(amount>=previous and amount<=target,"Counter monotonically approaches balance")
		previous = amount
	check(previous==target,"Counter reaches exact wallet value")
	check(Modal.displayed_balance(120,target,0,true)==target,"Reduced motion credits display immediately")
	check(Modal.coin_progress(0,0.5)==0.0 and Modal.coin_progress(13,10.0)<0.0,"Coins start after the card settles and all land")
	for age in [0.3,1.2,3.0]:
		game.modal.age = age
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/win-celebration-%d.png" % roundi(age*100))
	check(game.modal.tap("next") and game.model.level_index==1 and game.coins==target,"Next keeps the reward and opens the next level")
	game._load_level(0)
	finish(game)
	await process_frame
	await process_frame
	check(game.level_reward==0 and game.coins==target,"Replay has no new coin award")
	check(not game.modal.hits.has("double"),"Nothing to double without a reward")
	check(not game.modal.spec.blocks.any(func(b): return b.type=="reward"),"Replay has no coin reward block")
	game.modal.tap("replay")
	check(game.overlay=="" and game.model.level_index==0,"Replay restarts the level")
	# Doubling by rewarded video (simulated) from level 3, where it unlocks.
	game.ads.simulate = true
	game._load_level(2)
	game.rewarded_levels.erase(2)
	var before: int = game.coins
	finish(game)
	await process_frame
	await process_frame
	var reward: int = game.level_reward
	check(game.modal.tap("double"),"Double offered once the video is ready")
	await create_timer(1.5).timeout
	check(game.coins==before+reward*2 and game.reward_doubled and not game.modal.hits.has("double"),"Video doubles the reward exactly once")
	game.ads.simulate = false
	game.save_enabled = false
	game._cancel_animation()
	game.free()
	DirAccess.remove_absolute("user://win-celebration-test.cfg")
	await create_timer(0.35).timeout
	print("Win celebration: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
