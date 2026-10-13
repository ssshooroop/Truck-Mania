extends SceneTree

const Game = preload("res://scripts/main.gd")
var game
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func until(predicate:Callable,label:String) -> bool:
	var deadline := Time.get_ticks_msec()+15000
	while not predicate.call() and Time.get_ticks_msec()<deadline:
		await process_frame
	var ok:bool = predicate.call()
	check(ok,label)
	return ok

func _run() -> void:
	game = Game.new()
	root.add_child(game)
	game.automation = true
	game.save_enabled = false
	game.sound_enabled = false
	game._load_level(0)
	game.speed_factor = 0.3
	var initial:Dictionary = game.model.snapshot()
	game._dispatch(0)
	if await until(func(): return game.loading and not game.road_busy,"Worker begins loading with road free"):
		# Exercise dispatch while a worker transaction is outstanding.
		game._dispatch(1)
		check(game.model.get_bus(1).status == "arriving" and game.loading,"Second truck leaves during first loading")
		check(game.model.bays[0] == 0 and game.model.bays[1] == 1,"Each truck reserves a distinct bay immediately")
		game._open_settings()
		var worker:Vector2 = game.worker_position
		var truck:Vector2 = game.bus_visuals[1].position
		var angle:float = game.bus_visuals[1].angle
		var queue:Array = game.model.queue.duplicate()
		await create_timer(0.12).timeout
		check(worker == game.worker_position and truck == game.bus_visuals[1].position and angle == game.bus_visuals[1].angle and queue == game.model.queue,"Pause freezes concurrent worker and truck")
		game._resume()
		if await until(func(): return not game.busy,"Concurrent calls finish"):
			check(game.boarded == game.model.get_bus(0).capacity+game.model.get_bus(1).capacity,"Concurrent calls preserve exact cargo count")
			check(game.model.get_bus(0).status == "gone" and game.model.get_bus(1).status == "gone","Both trucks depart after complete loading")
			game._undo()
			check(game.model.snapshot() == initial and game.boarded == 0 and game.moves == 0,"Undo restores the pre-concurrency checkpoint")
	game._load_level(0)
	game._dispatch(0)
	if await until(func(): return game.loading and not game.road_busy,"Restart fixture reaches loading"):
		game._dispatch(1)
		game._open_settings()
		game._load_level(0)
		var restarted:Dictionary = game.model.snapshot()
		await create_timer(0.2).timeout
		check(game.model.snapshot() == restarted and not game.busy and not game.loading and not game.road_busy,"Restart cancels both concurrent animations")
	game.speed_factor = 0.015
	for level in game.model.level_count():
		game._load_level(level)
		for id in game.model.buses.size():
			if not await until(func(): return not game.road_busy and game.model.can_dispatch(id),"Concurrent level %d dispatch %d" % [level,id]): break
			game._dispatch(id)
		await until(func(): return not game.busy,"Concurrent level settles")
		check(game.model.is_won() and game.boarded == game.total_passengers,"All cargo delivered exactly once in concurrent level %d" % level)
	game._cancel_animation()
	print("Concurrent UI checks: %d; failures: %d" % [checks,failures])
	quit(0 if failures == 0 else 1)
