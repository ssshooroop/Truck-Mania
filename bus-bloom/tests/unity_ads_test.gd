extends SceneTree
const Ads = preload("res://scripts/ui/ad_service.gd")
class Bridge extends RefCounted:
	var calls:Array = []
	var loads:Array = []
	func show(unit:String,rewarded:bool,ticket:int) -> void: calls.append([unit,rewarded,ticket])
	func load(unit:String,rewarded:bool) -> void: loads.append([unit,rewarded])
var grants := 0
var availability_events := 0
func note_availability() -> void: availability_events += 1
func _initialize() -> void: run.call_deferred()
func request(ads,placement:String) -> void:
	if await ads.show_rewarded(placement): grants += 1
func run() -> void:
	var unavailable = Ads.new()
	unavailable.availability_changed.connect(note_availability)
	unavailable.initialize()
	assert(not Engine.has_singleton("TruckManiaAds")) # This suite runs on desktop.
	assert(unavailable.init_error=="sdk_unavailable" and unavailable.last_error=="sdk_unavailable")
	assert(not unavailable.initialized and not unavailable.is_ready("shop") and availability_events==1)
	var fake = Ads.new()
	fake.simulate = true
	fake.initialize()
	assert(fake.init_error.is_empty() and fake.errors_by_unit.is_empty() and fake.is_ready("shop"))
	var ads = Ads.new()
	ads.bridge = Bridge.new()
	ads.availability_changed.connect(note_availability)
	# Avoid launching an unrelated long retry timer in this callback-focused test.
	ads.init_retry_pending = true
	ads._on_initialized(false,"sdk_52005: Network error")
	assert(ads.init_error=="sdk_52005: Network error" and ads.last_error==ads.init_error)
	assert(not ads.initialized and ads.bridge.loads.is_empty() and availability_events==2)
	ads._on_initialized(false,"")
	assert(ads.init_error=="initialization_failed" and ads.last_error.is_empty())
	ads._on_initialized(true,"")
	assert(ads.init_error.is_empty() and ads.initialized and ads.bridge.loads.size()==6)
	assert(availability_events==4)
	var shop_unit:String = ads.config.rewarded.shop
	var undo_unit:String = ads.config.rewarded.undo
	ads.retry_pending[shop_unit] = true
	ads.retry_pending[undo_unit] = true
	ads._on_loaded(shop_unit,false,"sdk_52100: No ad fill")
	ads._on_loaded(undo_unit,true,"")
	assert(ads.errors_by_unit.get(shop_unit)=="sdk_52100: No ad fill")
	assert(not ads.is_ready("shop") and ads.is_ready("undo") and ads.last_error.is_empty())
	assert(ads.init_error.is_empty() and not ads.errors_by_unit.has(undo_unit))
	ads._on_loaded(undo_unit,false,"")
	assert(ads.errors_by_unit.get(undo_unit)=="load_failed" and not ads.is_ready("undo"))
	ads._on_loaded(shop_unit,true,"")
	assert(not ads.errors_by_unit.has(shop_unit) and ads.errors_by_unit.has(undo_unit))
	ads._on_loaded(undo_unit,true,"")
	assert(ads.errors_by_unit.is_empty())
	ads.ready.clear()
	assert(not ads.is_ready("undo"))
	for placement in ads.config.rewarded:
		var unit:String = ads.config.rewarded[placement]
		ads._on_loaded(unit,true,"")
		assert(ads.is_ready(placement))
		var before := grants
		request(ads,placement)
		assert(ads.watching and not ads.is_ready(placement))
		var ticket:int = ads.request_id
		request(ads,placement) # rapid repeated tap cannot start a second ad
		assert(ads.request_id==ticket)
		ads._on_finished(ticket-1,unit,true,"rewarded")
		ads._on_finished(ticket,"wrong_unit",true,"rewarded")
		assert(ads.watching and grants==before)
		ads._on_finished(ticket,unit,true,"rewarded")
		ads._on_finished(ticket,unit,true,"rewarded")
		assert(not ads.watching and grants==before+1)
	for reason in ["skipped","no_fill","network_error"]:
		ads.ready.undo = true
		var before := grants
		request(ads,"undo")
		ads._on_finished(ads.request_id,"undo",false,reason)
		assert(grants==before and not ads.watching)
		if reason!="skipped": assert(ads.errors_by_unit.get("undo")==reason)
	ads._on_loaded("undo",true,"")
	assert(not ads.errors_by_unit.has("undo"))
	ads.ready[ads.config.interstitial] = true
	for i in range(3): ads.note_level_completed()
	assert(not ads.interstitial_due())
	ads.note_level_completed()
	assert(ads.interstitial_due())
	ads.show_interstitial()
	ads._on_started(ads.request_id,ads.config.interstitial)
	ads._on_finished(ads.request_id,ads.config.interstitial,false,"closed")
	assert(ads.completions==0 and not ads.interstitial_due())
	for i in range(4): ads.note_level_completed()
	ads.ready[ads.config.interstitial] = true
	assert(not ads.interstitial_due()) # minimum interval, even after fast levels
	ads.last_ad_seconds = -100000.0
	assert(ads.interstitial_due())
	ads.ready.undo = true
	request(ads,"undo")
	ads._on_started(ads.request_id,"undo")
	ads._on_finished(ads.request_id,"undo",true,"rewarded")
	assert(ads.completions==0 and not ads.interstitial_due())
	print("PASS: missing SDK, explicit simulation, initialization diagnostics, independent placement errors, all 5 reward placements, duplicate/stale callbacks, skip/failure, concurrent tap, interstitial interval/cooldown.")
	quit()
