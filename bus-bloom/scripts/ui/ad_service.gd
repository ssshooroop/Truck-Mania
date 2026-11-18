extends RefCounted
## Native Android SDK; desktop/web unavailable except explicit simulation.
signal availability_changed
signal completed(reward:bool)
signal presentation_changed(active:bool)
var config:Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/ads.json"))
var simulate := false
var watching := false
var bridge:Object
var ready:Dictionary = {}
var initialized := false
var request_id := 0
var active_unit := ""
var last_error := ""
## Keep initialization and placement failures independent: another successful
## placement must not erase the reason an unavailable button cannot load.
var init_error := ""
var errors_by_unit:Dictionary = {}
var completions := 0
var last_ad_seconds := -100000.0
var retry_pending:Dictionary = {}
var init_retry_pending := false

func initialize() -> void:
	if simulate: return
	if not Engine.has_singleton("TruckManiaAds"):
		init_error = "sdk_unavailable"
		last_error = init_error
		availability_changed.emit()
		return
	bridge = Engine.get_singleton("TruckManiaAds")
	bridge.connect("initialized",_on_initialized,CONNECT_DEFERRED)
	bridge.connect("loaded",_on_loaded,CONNECT_DEFERRED)
	bridge.connect("started",_on_started,CONNECT_DEFERRED)
	bridge.connect("finished",_on_finished,CONNECT_DEFERRED)
	bridge.initialize(str(config.android_game_id),bool(config.test_mode))

func _on_initialized(ok:bool,error:String) -> void:
	initialized = ok
	last_error = error
	init_error = "" if ok else (error if not error.is_empty() else "initialization_failed")
	availability_changed.emit()
	if ok:
		for unit in config.rewarded.values(): bridge.load(str(unit),true)
		bridge.load(str(config.interstitial),false)
	elif not init_retry_pending:
		init_retry_pending = true
		await Engine.get_main_loop().create_timer(30.0).timeout
		init_retry_pending = false
		if is_instance_valid(bridge): bridge.initialize(str(config.android_game_id),bool(config.test_mode))

func _on_loaded(unit:String,ok:bool,error:String) -> void:
	ready[unit] = ok
	last_error = error
	if ok: errors_by_unit.erase(unit)
	else: errors_by_unit[unit] = error if not error.is_empty() else "load_failed"
	availability_changed.emit()
	if not ok: _retry(unit)

func _retry(unit:String) -> void:
	if retry_pending.has(unit): return
	retry_pending[unit] = true
	await Engine.get_main_loop().create_timer(30.0).timeout
	retry_pending.erase(unit)
	if initialized and is_instance_valid(bridge) and not ready.get(unit,false) and active_unit!=unit:
		bridge.load(unit,unit!=str(config.interstitial))

func is_ready(placement:String="double") -> bool:
	return not watching and (simulate or bool(ready.get(str(config.rewarded.get(placement,"")),false)))

func note_level_completed() -> void:
	completions = mini(completions+1,int(config.interstitial_interval))

func interstitial_due() -> bool:
	return not watching and completions>=int(config.interstitial_interval) \
		and Time.get_ticks_msec()/1000.0-last_ad_seconds>=float(config.interstitial_cooldown_seconds) \
		and (simulate or bool(ready.get(str(config.interstitial),false)))

func show_rewarded(placement:String="double") -> bool:
	if not is_ready(placement): return false
	return await _show(str(config.rewarded[placement]),true)

func show_interstitial() -> void:
	if interstitial_due(): await _show(str(config.interstitial),false)

func _show(unit:String,rewarded:bool) -> bool:
	watching = true
	request_id += 1
	active_unit = unit
	ready[unit] = false
	last_error = ""
	presentation_changed.emit(true)
	availability_changed.emit()
	if simulate:
		await Engine.get_main_loop().create_timer(1.2).timeout
		_on_started(request_id,unit)
		_finish(rewarded,"rewarded" if rewarded else "closed")
		return rewarded
	bridge.show(unit,rewarded,request_id)
	var earned:bool = await completed
	return earned

func _on_started(ticket:int,unit:String) -> void:
	if not watching or ticket!=request_id or unit!=active_unit: return
	# Rewarded ads restart interstitial spacing too; never show both in succession.
	completions = 0
	last_ad_seconds = Time.get_ticks_msec()/1000.0

func _on_finished(ticket:int,unit:String,earned:bool,reason:String) -> void:
	# Ignore duplicate, stale or mismatched callbacks.
	if not watching or ticket!=request_id or unit!=active_unit: return
	_finish(earned and unit in config.rewarded.values(),reason)

func _finish(earned:bool,reason:String) -> void:
	var unit := active_unit
	active_unit = ""
	watching = false
	last_error = reason
	if reason not in ["rewarded","skipped","closed"]:
		errors_by_unit[unit] = reason if not reason.is_empty() else "show_failed"
	presentation_changed.emit(false)
	completed.emit(earned)
	availability_changed.emit()
	if initialized and is_instance_valid(bridge): bridge.load(unit,unit!=str(config.interstitial))
