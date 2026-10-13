extends SceneTree
const Game = preload("res://scripts/main.gd")
var game
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok:bool,message:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func wait_for(predicate:Callable) -> void:
	var deadline := Time.get_ticks_msec()+8000
	while not predicate.call() and Time.get_ticks_msec()<deadline: await process_frame
	check(predicate.call(),"Animation reaches expected state")

func _run() -> void:
	game = Game.new()
	root.add_child(game)
	game.automation = true
	game.save_enabled = false
	game.sound_enabled = false
	game.speed_factor = 0.2
	var tested := 0
	for level in game.model.level_count():
		game._load_level(level)
		for bus:Dictionary in game.model.buses:
			if game.model.blocking_ids(bus.id).is_empty(): continue
			var hit:Dictionary = game.Contact.contact(game.model,bus.id)
			check(not hit.is_empty(),"Blocked truck has visible contact")
			if hit.is_empty(): continue
			check(hit.distance>=0 and hit.distance<game.model.exit_position(bus.id).distance_to(bus.position),"Contact occurs before leaving the yard")
			var state:Dictionary = game.model.snapshot()
			await game._dispatch(bus.id)
			check(game.model.snapshot()==state and game.moves==0 and game.history.is_empty(),"Bump does not change model, cargo, moves or undo")
			check(game.bus_visuals[bus.id].position==bus.position and not game.road_busy,"Bump returns exactly to origin and releases road")
			check(game.impact.obstacle==hit.obstacle,"Waves mark the first visible obstacle")
			tested += 1
	game._load_level(0)
	game.speed_factor = 1.0
	var id := -1
	for bus:Dictionary in game.model.buses:
		if not game.model.blocking_ids(bus.id).is_empty():
			id = bus.id
			break
	game._dispatch(id)
	game._open_settings()
	var position:Vector2 = game.bus_visuals[id].position
	await create_timer(0.1).timeout
	check(game.bus_visuals[id].position==position,"Pause freezes the bump")
	game._resume()
	await wait_for(func(): return not game.road_busy)
	game._dispatch(id)
	game._load_level(0)
	var state:Dictionary = game.model.snapshot()
	await create_timer(0.7).timeout
	check(game.model.snapshot()==state and not game.busy and game.impact.is_empty(),"Restart clears the bump and waves")
	print("Bump checks: %d; blocked vehicles: %d; failures: %d" % [checks,tested,failures])
	quit(0 if failures==0 else 1)
