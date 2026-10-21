extends SceneTree

const Probe = preload("res://tests/motion_probe.gd")
var failures := 0
var probe

func _initialize() -> void:
	probe = Probe.new()
	root.add_child.call_deferred(probe)
	_run.call_deferred()

func _run() -> void:
	var selected: Array = range(probe.model.level_count())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--levels="):
			selected.clear()
			for number in arg.trim_prefix("--levels=").split(","): selected.append(int(number)-1)
	for level in selected:
		probe._load_level(level)
		var steps := 0
		while not probe.model.is_won() and steps < 40:
			var id: int = probe.model.find_hint()
			if id < 0:
				push_error("Motion test has no solving dispatch for level %d" % (level + 1))
				failures += 1
				break
			await probe._dispatch(id)
			steps += 1
		if not probe.model.is_won():
			failures += 1
		print("MOTION_LEVEL_%d_FINISHED fleet=%d delivered=%d" % [level + 1, steps, probe.boarded])
	print("Motion segments: %d; samples: %d; body-pair checks: %d; colliding segments: %d; other failures: %d" % [probe.motion_segments, probe.motion_samples, probe.pair_checks, probe.collision_segments, failures])
	print("Invisible vehicle samples: ",probe.invisible_samples)
	quit(0 if failures == 0 and probe.collision_segments == 0 and probe.invisible_samples == 0 else 1)
