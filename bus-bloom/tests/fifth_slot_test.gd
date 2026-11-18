extends SceneTree
const Game=preload("res://scripts/main.gd")
const Modals=preload("res://scripts/ui/modal_catalog.gd")
func _initialize(): run.call_deferred()
func has_action(spec:Dictionary,id:String) -> bool:
	for block in spec.blocks:
		if block.get("id","")==id: return true
	return false
func run():
	var g=Game.new()
	g.automation=true
	g.save_enabled=false
	root.add_child(g)
	await process_frame
	g._load_level(18)
	g._cancel_animation()
	g.overlay="stuck"
	g.busy=false
	g.coins=1000
	g.economy.state.inventory.extra_slot=0
	g.economy.state.tutorial_done=true
	g.rescue_count=int(g.economy.config.rescue.max_tools)
	g._on_stuck_action("slot_coins")
	assert(g.model.open_bay_count==4)
	g.overlay="stuck"
	var ctx:Dictionary=g._stuck_context()
	assert(not ctx.rescue_left and ctx.slot_available)
	assert(has_action(Modals.stuck(ctx),"slot_coins"))
	assert(has_action(Modals.stuck(ctx),"slot_ad"))
	var balance:int=g.coins
	var price:int=g._slot_price()
	g._on_stuck_action("slot_coins")
	assert(g.model.open_bay_count==5 and g.coins==balance-price)
	assert(not has_action(Modals.stuck(g._stuck_context()),"slot_coins"))
	g._purchase_slot()
	assert(g.coins==balance-price)
	g._load_level(18)
	g._cancel_animation()
	g.busy=false
	g.overlay="stuck"
	assert(g.model.open_bay_count==3)
	g.model.unlock_next_bay()
	g.rescue_count=10
	g.offered_bay=4
	g.coins=0
	g._purchase_slot()
	assert(g.model.open_bay_count==4)
	# Called only after the rewarded-ad callback; no ad readiness is bypassed in UI.
	g._purchase_slot(true)
	assert(g.model.open_bay_count==5 and g.coins==0)
	g.queue_free()
	await process_frame
	print("Level 19: fourth/fifth slots after rescue limit, price, duplicate guard, ad reward and restart passed")
	quit()
