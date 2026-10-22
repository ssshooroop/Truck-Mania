extends SceneTree
## Modal windows wired into the game: dead end, paid undo, shortfall, cone
## confirmation, rewarded video (simulated), tutorial and seasonal schedule.
const Game = preload("res://scripts/main.gd")
const Catalog = preload("res://scripts/ui/modal_catalog.gd")
var failures := 0
var checks := 0
func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func _initialize() -> void: run.call_deferred()
func frames(n:int=2) -> void:
	for i in n: await process_frame
func modal_id(g) -> String:
	return "" if g.modal==null else String(g.modal.spec.get("id",""))
func stuck(g) -> void:
	g._load_level(3)
	g.intro_delays.clear()
	g.history.append({"state":g.model.undo_snapshot(),"moves":0,"boarded":0})
	g.overlay = "stuck"
	await frames()
func run() -> void:
	root.size = Vector2i(540,1171)
	var g = Game.new()
	g.automation = true
	g.save_enabled = false
	root.add_child(g)
	g.economy.state.tutorial_done = true
	await frames()

	# Dead end opens its window and lifts the coin badge into it.
	g.coins = 120
	await stuck(g)
	check(modal_id(g)=="stuck","Dead end shows the parking-full window")
	check(not g.coin_badge.visible,"Window draws the balance instead of the game badge")
	check(g.modal.tap("undo") and g.coins==100 and g.overlay=="","Paid undo charges 20 and resumes play")
	await create_timer(0.3).timeout
	check(g.modal==null,"Window closes when play resumes")

	# Too poor for undo: the shortfall window replaces it, closing returns.
	g.coins = 5
	await stuck(g)
	g.modal.tap("undo")
	await frames()
	check(modal_id(g)=="shortfall" and g.coins==5,"Shortfall instead of a silent failure")
	g.modal.tap("close")
	await create_timer(0.3).timeout
	check(modal_id(g)=="stuck","Closing the shortfall returns to the dead end")

	# Buying the slot from the dead end.
	g.coins = 150
	g.modal.update_spec(Catalog.stuck(g._stuck_context()))
	check(g.modal.tap("slot_coins") and g.coins==50 and g.model.open_bay_count==4,"Slot bought for 100")
	check(not g.modal.tap("slot_ad") or g.model.open_bay_count==4,"Ad button inert without an ad")

	# Rewarded video pays for a slot, coins untouched.
	g.ads.simulate = true
	await stuck(g)
	check(g.modal.tap("slot_ad") and g.modal.busy.has("slot_ad"),"Ad shows a loading state")
	await create_timer(1.5).timeout
	check(g.model.open_bay_count==4 and g.coins==50,"Finished video opens the slot for free")
	g.ads.simulate = false

	# Cone during play asks before charging.
	g._load_level(3)
	g.intro_delays.clear()
	g.coins = 120
	g._tap_cone(3)
	await frames()
	check(modal_id(g)=="offer_extra_slot" and g.coins==120,"Cone tap asks first")
	g.modal.back()
	await create_timer(0.3).timeout
	check(g.modal==null and g.model.open_bay_count==3,"Back dismisses without buying")
	g._tap_cone(3)
	await frames()
	g.modal.tap("buy")
	check(g.coins==20 and g.model.open_bay_count==4,"Confirmed cone costs 100")
	g._tap_cone(4)
	await frames()
	g.modal.tap("buy")
	await frames()
	check(modal_id(g)=="shortfall" and g.model.open_bay_count==4,"Second cone without coins shows the shortfall")

	# Shortfall paid by video: coins arrive and the reward state shows.
	g.ads.simulate = true
	g.modal.update_spec(Catalog.shortfall(100,g.coins,25,true))
	g.modal.tap("watch_ad")
	await create_timer(1.5).timeout
	check(g.coins==45 and modal_id(g)=="ad_reward","Video grants 25 coins and shows the reward")
	g.ads.simulate = false

	# Tutorial: three coach steps, then play.
	g.economy.state.intro_seen = false
	g._load_level(0)
	g._start_tutorial(g.generation)
	await create_timer(1.3).timeout
	check(g.overlay=="tutorial" and modal_id(g)=="tutorial" and g.modal.spec.has("spotlight"),"Tutorial step 1 highlights a truck")
	g.modal.tap("tutorial_next")
	g.modal.tap("tutorial_next")
	check(int(g.modal.spec.blocks[1].index)==2,"Steps advance")
	g.modal.tap("tutorial_next")
	await create_timer(0.3).timeout
	check(g.overlay=="" and g.modal==null and g.economy.state.intro_seen,"Tutorial finishes into play and is remembered")

	# Store unavailable: nothing is charged or granted.
	g.coins = 10
	g._open_shop(["road_menu"])
	g.overlay = "road_menu"
	await frames()
	check(modal_id(g)=="shop" and g.modal.tap("buy:coins_500") and g.coins==10,"No store, no coins")
	# Simulated store: pack arrives after confirmation, then the receipt shows.
	g.store.simulate = true
	g.modal.tap("buy:coins_1200")
	check(g.modal.busy.has("buy:coins_1200"),"Purchase shows a loading state")
	await create_timer(1.3).timeout
	check(g.coins==1210 and modal_id(g)=="received","Pack granted once confirmed")
	g._open_shop(["road_menu"])
	await frames()
	g.modal.tap("buy:starter")
	await create_timer(1.3).timeout
	check(g.coins==1810 and int(g.economy.state.inventory.get("extra_slot",0))==3 and "starter" in g.economy.state.purchases,"Starter bundle grants items and is remembered")
	g._open_shop(["road_menu"])
	await frames()
	var ids: Array = []
	for b in g.modal.spec.blocks: if b.type=="deal": ids.append(b.id)
	check("buy:starter" not in ids,"One-time bundle leaves the shop")
	check(g.store.bonus("coins_2600")=="+30%" and g.store.pack_for(110)=="coins_500" and g.store.pack_for(99999)=="coins_12000","Pack bonus and best fit")
	g.store.simulate = false
	g._close_modal(true)

	# Menu during a level: pause with Continue / Restart, switch, sub-windows.
	g._load_level(3)
	g.intro_delays.clear()
	g.reduced_motion = false
	g._open_settings()
	await frames()
	check(modal_id(g)=="menu" and g.modal.hits.has("resume") and g.modal.hits.has("restart"),"In-level menu offers Continue and Restart")
	g.modal.tap("motion")
	check(g.reduced_motion and g.modal.spec.blocks[1].on,"Switch reduces motion at once")
	g.modal.tap("motion")
	g.modal.tap("language")
	await frames()
	check(modal_id(g)=="languages" and not g.modal.hits.has("lang:en") and not g.modal.hits.has("lang:ru"),"Only ready, non-current languages are selectable")
	g.modal.tap("close")
	await create_timer(0.3).timeout
	check(modal_id(g)=="menu","Closing a sub-window returns to the menu")
	g.modal.tap("support")
	await frames()
	g.modal.tap("write")
	check(modal_id(g)=="support" and g.modal.flash_time>0.0,"Support without an address explains instead of failing")
	check(String(g.economy.state.player_id).length()==9 or String(g.economy.state.player_id)=="","Player id has the XXXX-XXXX shape")
	g.modal.tap("close")
	await create_timer(0.3).timeout
	g.modal.tap("resume")
	check(g.overlay=="","Continue resumes the level")
	await create_timer(0.3).timeout
	# Menu from the map floats over it and closes back to it.
	g._show_road_menu(false)
	g._open_settings()
	await frames()
	check(modal_id(g)=="menu" and not g.modal.hits.has("resume") and g.road_menu.visible,"Map menu keeps the map and has no Continue")
	g.modal.tap("close")
	check(g.overlay=="road_menu","Closing returns to the map")
	await create_timer(0.3).timeout

	# Seasonal schedule.
	var events: Array = Catalog.load_events()
	var oct := int(Time.get_unix_time_from_datetime_string("2026-10-21T12:00:00"))
	var nov := int(Time.get_unix_time_from_datetime_string("2026-11-20T12:00:00"))
	check(Catalog.active_event(events,oct).get("id","")=="halloween_2026","Halloween promo active in October")
	check(Catalog.active_event(events,nov).is_empty(),"No promo between seasons")
	check(Catalog.coin_word(1)=="монета" and Catalog.coin_word(3)=="монеты" and Catalog.coin_word(11)=="монет","Russian plurals")

	g.queue_free()
	await frames()
	print("Modal flow: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
