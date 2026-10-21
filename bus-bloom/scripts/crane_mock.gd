extends "res://scripts/main.gd"
## Visual mock only: no reward, charge or crane action is performed.
func _ready():
	automation=true
	save_enabled=false
	super._ready()
	_load_level(3)
	intro_delays.clear()
	overlay="crane_preview"
func _input(_event:InputEvent):
	pass
