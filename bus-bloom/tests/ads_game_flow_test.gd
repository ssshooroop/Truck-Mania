extends SceneTree
class Bridge extends RefCounted:
	func show(_unit:String,_rewarded:bool,_ticket:int) -> void: pass
	func load(_unit:String,_rewarded:bool) -> void: pass
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var game=preload("res://scripts/main.gd").new()
	game.save_enabled=false
	game.automation=true
	root.add_child(game)
	game.ads.bridge=Bridge.new()
	game._show_road_menu(false)
	game._open_shop(["road_menu"])
	var tile:Dictionary
	for block in game.modal.spec.blocks:
		if block.type=="packs": tile=block.tiles[0]
	assert(not tile.enabled)
	game.modal._layout()
	assert(not game.modal.hits.has("free_coins"))
	game.ads._on_loaded("25_coins_store",true,"")
	assert(tile.enabled and tile.price=="Бесплатно")
	var before:int=game.coins
	assert(game.modal.tap("free_coins"))
	assert(paused and game.ads.watching and game.modal.input_locked)
	assert(AudioServer.is_bus_mute(0))
	game._back()
	assert(game.modal!=null)
	game.ads._on_finished(game.ads.request_id,"25_coins_store",false,"skipped")
	assert(game.coins==before and not paused and game.overlay=="road_menu")
	game.ads._on_loaded("25_coins_store",true,"")
	game.modal.action.emit("free_coins")
	var ticket:int=game.ads.request_id
	game.ads._on_finished(ticket,"25_coins_store",true,"rewarded")
	assert(game.coins==before+25 and not paused)
	game.ads._on_finished(ticket,"25_coins_store",true,"rewarded")
	assert(game.coins==before+25)
	game._close_modal(true)
	game.overlay="win"
	game.level_reward=20
	game.reward_doubled=false
	game._sync_modals()
	game.ads._on_loaded("double_reward",true,"")
	before=game.coins
	game._on_win_action("double")
	game._on_win_action("next")
	assert(paused and game.ads.watching)
	game.ads._on_finished(game.ads.request_id,"double_reward",true,"rewarded")
	assert(game.reward_doubled and game.coins==before+20 and game.overlay=="win")
	game._on_win_action("double")
	assert(game.coins==before+20 and not game.ads.watching)
	game._load_level(18)
	before=game.coins
	for expected in [4,5]:
		game.overlay="stuck"
		game.ads._on_loaded("open_slot",true,"")
		game._on_stuck_action("slot_ad")
		game.ads._on_finished(game.ads.request_id,"open_slot",true,"rewarded")
		assert(game.model.open_bay_count==expected and game.coins==before)
	game._open_shortfall(game.coins+100,[game.overlay])
	game.ads._on_loaded("25_coins_level",true,"")
	assert(game.modal.tap("watch_ad"))
	game.ads._on_finished(game.ads.request_id,"25_coins_level",true,"rewarded")
	assert(game.coins==before+25)
	game.queue_free()
	await process_frame
	print("PASS: live shop refresh, exact-once coins, skip, pause/audio/input lock, double reward, navigation guard, fourth/fifth slots, shortfall coins")
	quit()
