extends SceneTree
const Game = preload("res://scripts/main.gd")
var failures := 0
var checks := 0
func check(value:bool,label:String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	_run.call_deferred()
func capture(name:String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/slots-"+name+".png")
func _run() -> void:
	root.size = Vector2i(540,1171)
	var game = Game.new()
	root.add_child(game)
	game.automation = true
	game.save_enabled = false
	game._sync_audio_preferences()
	game.coins = 40
	game._load_level(2)
	check(game.model.open_bay_count==3,"Three bays open initially")
	check(game.model.free_bay([0,1,2,-1,-1])==-1,"Locked bays are not free spaces")
	var before:Dictionary = game.model.snapshot()
	await capture("cones")
	game._open_slot_offer(4)
	game._purchase_slot()
	check(game.model.open_bay_count==3,"Fifth bay cannot bypass fourth")
	game._close_slot_offer()
	game._open_slot_offer(3)
	await capture("tutorial")
	var gameplay_time: float = game.elapsed
	var glow_time: float = game.spotlight_time
	await create_timer(0.12).timeout
	check(game.spotlight_time>glow_time and game.elapsed==gameplay_time,"Glow animates while gameplay stays paused")
	game._overlay_input(Vector2(270,530))
	check(game.model.open_bay_count==3 and game.overlay=="slot_offer","Text and background taps cannot open a slot")
	game._overlay_input(game._cone_position(3))
	check(game.model.open_bay_count==4 and game.coins==40,"Tutorial bay is free")
	game._purchase_slot()
	check(game.model.open_bay_count==4,"Duplicate purchase does nothing")
	check(game.model.restore(before) and game.model.open_bay_count==4,"Undo retains the attempt upgrade")
	game._show_road_menu(true)
	game._resume_from_menu()
	check(game.model.open_bay_count==4,"Menu resume retains the attempt upgrade")
	game._open_slot_offer(4)
	game._purchase_slot()
	check(game.model.open_bay_count==5 and game.coins==40,"Fifth tutorial bay also opens free")
	game._load_level(2)
	check(game.model.open_bay_count==3,"Restart closes extra bays")
	game._load_level(3)
	game._open_slot_offer(3)
	game._purchase_slot()
	check(game.model.open_bay_count==3 and game.coins==40,"Unconfigured prices cannot spend or grant slots")
	game._overlay_input(Vector2(270,620))
	check(game.model.open_bay_count==3,"Unavailable advertising grants no reward")
	game._close_slot_offer()
	check(game.overlay=="","Offer closes back to play")
	game.free()
	await create_timer(0.35).timeout
	print("Slots: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
