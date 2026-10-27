extends SceneTree
const Calendar=preload("res://scripts/daily_calendar.gd")
func _initialize():
	var c=Calendar.new()
	assert(c.claim(100)==0)
	assert(c.claim(100)==-1)
	assert(c.claim(102)==2)
	assert(c.view(102).cards[1]=="missed")
	assert(c.claim(106)==6) # Three missing days, no reset.
	assert(c.claim(107)==0) # New seven-day cycle.
	assert(c.claim(112)==0) # Four missing days resets.
	var restored=Calendar.new()
	restored.restore(c.state.duplicate(true))
	assert(restored.claim(112)==-1)
	assert(restored.claim(111)==-1)
	assert(restored.claim(113)==1)
	# Midnight refresh persisted before claiming: yesterday stays missed.
	var pending=Calendar.new()
	pending.visit(200)
	pending.visit(201)
	var saved=ConfigFile.new()
	saved.set_value("daily","state",pending.state)
	var loaded=ConfigFile.new()
	assert(loaded.parse(saved.encode_to_text())==OK)
	var midnight=Calendar.new()
	midnight.restore(loaded.get_value("daily","state"))
	assert(midnight.view(201).cards[0]=="missed")
	assert(midnight.claim(201)==1)
	assert(midnight.claim(201)==-1)
	var claimed=Calendar.new()
	claimed.restore(midnight.state.duplicate(true))
	assert(claimed.claim(201)==-1)
	assert(claimed.claim(200)==-1)
	assert(claimed.claim(202)==2)
	print("Daily calendar: skip, reset threshold, cycle, restore and duplicate claims passed")
	quit()

