extends SceneTree
class Probe:
	extends "res://scripts/main.gd"
	var heard:Array = []
	func _sound_effect(key:String) -> void: heard.append(key)
	func _draw() -> void: pass
var failures := 0
func check(ok:bool,label:String):
	print(label,": ",ok)
	if not ok: failures+=1
func _initialize(): run.call_deferred()
func run():
	var g=Probe.new()
	root.add_child(g)
	g.save_enabled=false
	g.automation=true
	g._load_level(3)
	g._update_truck_idle(14.9)
	check(g.heard.is_empty(),"No early horn")
	g._update_truck_idle(0.11)
	check(g.heard==["horn"] and g.model.can_dispatch(g.horn_bus),"After 15 seconds only an available truck honks")
	var first=g.horn_bus
	g._update_truck_idle(15.0)
	check(g.horn_bus!=first,"Idle reminder rotates among available trucks")
	g.loading=true
	g._update_truck_idle(20.0)
	check(g.heard.size()==2 and g.horn_bus==-1,"No horn or sway while loading")
	g.loading=false
	g.overlay="settings"
	g._update_truck_idle(20.0)
	check(g.heard.size()==2,"No horn in menus")
	g.overlay=""
	g._reset_truck_idle()
	g.heard.clear()
	var path=[{"position":Vector2(10,500),"angle":0.0,"distance":0.0},{"position":Vector2(10,200),"angle":0.0,"distance":300.0}]
	g.traffic.routes[0]={"path":path,"delay":1.0,"duration":2.0,"elapsed":0.0}
	g.traffic.advance(g,0.9)
	check(g.heard.is_empty(),"Reserved truck stays silent before movement")
	g.traffic.advance(g,0.2)
	check(g.heard==["start"],"Engine starts once when movement begins")
	g.traffic.advance(g,1.8)
	check(g.heard==["start","skid"],"Skid plays once near bay arrival")
	g.traffic.advance(g,0.2)
	check(g.heard==["start","skid"],"No duplicate arrival sounds")
	g._cancel_animation()
	g.queue_free()
	await process_frame
	print("Truck sound failures: ",failures)
	quit(1 if failures else 0)
