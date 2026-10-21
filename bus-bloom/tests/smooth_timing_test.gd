extends SceneTree
const Game = preload("res://scripts/main.gd")
var failures := 0
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var game = Game.new()
	root.add_child(game)
	game.automation = true
	game.save_enabled = false
	game._sync_audio_preferences()
	game.reduced_motion = false
	for level in [0,1,2]:
		game._load_level(level)
		var id: int = game.model.find_hint()
		var bus: Dictionary = game.model.get_bus(id)
		var size: Vector2 = game.model.vehicle_size(bus)
		var previous: Vector2 = game.EdgeRoute.position_for(bus.position,bus.angle,size)
		var angle: float = bus.angle
		var previous_time := Time.get_ticks_msec()
		var stationary := 0.0
		var longest_stop := 0.0
		var moving_turn_samples := 0
		var deadline := previous_time+12000
		game._dispatch(id)
		while bus.status=="arriving" and Time.get_ticks_msec()<deadline:
			await process_frame
			var now := Time.get_ticks_msec()
			var visual: Dictionary = game.bus_visuals[id]
			var point: Vector2 = game.EdgeRoute.position_for(visual.position,visual.angle,size)
			var moved: bool = point.distance_to(previous)>0.05
			var turned: bool = absf(angle_difference(angle,visual.angle))>0.002
			if moved and turned: moving_turn_samples += 1
			stationary = 0.0 if moved or turned else stationary+(now-previous_time)/1000.0
			longest_stop = maxf(longest_stop,stationary)
			previous = point
			angle = visual.angle
			previous_time = now
		if bus.status=="arriving" or moving_turn_samples<2 or longest_stop>0.12:
			failures += 1
		print("Smooth arrival level=%d moving_turn_samples=%d longest_stop=%.3f" % [level+1,moving_turn_samples,longest_stop])
	game._cancel_animation()
	await process_frame
	game.free()
	await create_timer(0.35).timeout
	print("Smooth timing failures: ",failures)
	quit(1 if failures else 0)
