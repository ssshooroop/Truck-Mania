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
	print("Daily calendar: skip, reset threshold, cycle, restore and duplicate claims passed")
	quit()
