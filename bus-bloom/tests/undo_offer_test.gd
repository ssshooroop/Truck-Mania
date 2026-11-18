extends SceneTree
class Game:
	extends "res://scripts/main.gd"
	func _settle(_ticket:int): pass
func _initialize():run.call_deferred()
func prepare(g):
	g._load_level(0);g._cancel_animation();g.overlay="";g.busy=false
	var state=g.model.undo_snapshot()
	for b in g.model.buses:
		if g.model.can_dispatch(b.id):
			g.model.dispatch(b.id);g.model.arrive(b.id);break
	g.history=[{"state":state,"moves":0,"boarded":0}]
func run():
	var g=Game.new();g.automation=true;g.save_enabled=false;root.add_child(g)
	prepare(g);g.coins=50;g.economy.state.inventory.undo=2
	g._open_undo_offer()
	assert(g.history.is_empty() and g.coins==50 and g.economy.state.inventory.undo==1 and g.modal==null)
	g._open_undo_offer();assert(g.economy.state.inventory.undo==1)
	prepare(g);g.economy.state.inventory.undo=0
	g._open_undo_offer();assert(g.modal.spec.id=="offer_undo" and g.coins==50 and g.history.size()==1)
	g.modal.action.emit("buy");assert(g.coins==30 and g.history.is_empty())
	prepare(g);g.coins=0;g.ads.simulate=true;g._open_undo_offer()
	g.modal.action.emit("watch_ad")
	await create_timer(1.5).timeout
	assert(g.history.is_empty() and g.coins==0)
	prepare(g)
	g.model.bays[0]=0;g.model.bays[1]=1;g.model.bays[2]=2
	assert(g.model.crane_bay()==5 and g.model.open_bay_count==3)
	g.model.bays[1]=-1;assert(g.model.crane_bay()==1)
	g.queue_free();await process_frame
	print("Undo: free, paid, ad and empty history passed; crane slot priority passed")
	quit()
