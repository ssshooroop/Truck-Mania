extends Node2D

const Model = preload("res://scripts/game_model.gd")
const Contact = preload("res://scripts/collision_feedback.gd")
var daily_screen
var daily_rewards=preload("res://scripts/daily_rewards.gd").new()
var crane_preview
const SlotOffer = preload("res://scripts/slot_offer.gd")
const AD_ICON = preload("res://assets/artwork/menu/ad-player.png")
const EdgeRoute = preload("res://scripts/edge_route.gd")
const TruckRoute = preload("res://scripts/truck_route.gd")
const Art = preload("res://scripts/cargo_art.gd")
const CoinBadge = preload("res://scripts/coin_badge.gd")
const WinCelebration = preload("res://scripts/win_celebration.gd")
const Economy = preload("res://scripts/runtime_economy.gd")
const Boosters = preload("res://scripts/level_boosters.gd")
const GameModal = preload("res://scripts/ui/game_modal.gd")
const Modals = preload("res://scripts/ui/modal_catalog.gd")
const AdService = preload("res://scripts/ui/ad_service.gd")
const StoreService = preload("res://scripts/ui/store_service.gd")
const UNDO_PRICE = 20
var modal_layer: CanvasLayer
var modal: Control
var modal_scope: Array = []
var ads = AdService.new()
var store = StoreService.new()
var tutorial_step = 0
var reward_doubled = false
const INK = Color("152b46")
const MUTED = Color("536780")
const PAPER = Color("b2b0b6")
const FACTORY = preload("res://assets/artwork/cargo/Background-factory.png")
const Layout = preload("res://scripts/responsive_layout.gd")
var draw_base := Transform2D.IDENTITY

func art_transform(offset:Vector2,angle:float=0.0,zoom:Vector2=Vector2.ONE) -> void:
	draw_set_transform_matrix(draw_base*Transform2D(angle,zoom,0.0,offset))

func _draw_space(value:Transform2D) -> void:
	draw_base = value
	art_transform(Vector2.ZERO)

func _world_transform() -> Transform2D:
	if model.tablet_layout: return Transform2D.IDENTITY
	return Layout.world(get_viewport_rect().size)

func _panel_transform() -> Transform2D:
	return Layout.panel(get_viewport_rect().size)

func _footer_y() -> float:
	return get_viewport_rect().size.y-46.0
const GAME_ICONS = [
	preload("res://assets/artwork/menu/undo.png"),
	preload("res://assets/artwork/menu/bulb.png"),
	preload("res://assets/artwork/menu/door-back.png")
]
var game_icon_regions: Array[Rect2] = []
const ACCENT = Color("ffc400")
const BAY_X = [87.0, 164.0, 240.0, 316.0, 393.0]
const BAY_ANGLE = -27.0 * PI / 180.0
var ROAD_Y = 516.0
var WALKWAY_Y = 465.0
const BELT_STEP = 60.0
const BELT_BOTTOM = 315.0*540.0/1179.0 # Lower edge of the moving belt in the original artwork.
const BELT_CARGO_SIZE = Vector2(115,130)*540.0/1179.0
const WORKER_HOME = Vector2(468,185)
const SAVE_PATH = "user://cargo_yard_playtest10_c3a0f1c.cfg"

var model = Model.new()
var art
var font: Font
var bus_visuals: Dictionary = {}
var intro_age := 0.0
var intro_delays: Dictionary = {}
var history: Array = []
var busy = false
var road_busy = false
var arrival_ids:Dictionary = {}
var traffic = preload("res://scripts/arrival_traffic.gd").new()
var pending_dispatch := -1
var loading = false
var motion_tween: Tween
var paused_motion_tween: Tween
var overlay = ""
var levels_origin = "settings"
var road_menu
var menu_settings = false
var slot_pops: Array = []
var offered_bay = -1
var spotlight_time = 0.0
var juicy_font: FontVariation
var slot_return_overlay = ""
var elapsed = 0.0
var active_tween: Tween
var paused_tween: Tween
var generation = 0
var boarded = 0
var total_passengers = 0 # Cargo units; retained for regression test compatibility.
var moves = 0
var unlocked = 0
var economy = Economy.new()
var coins = int(economy.config.start_balance)
var rescue_count = 0
var paid_slots = 0
var attempt_rescued = false
var attempt_failed = false
var tutorial_prompted = false
var peak_bays = 0
var reward_details: Dictionary = {}
var rewarded_levels: Array[int] = []
var level_reward = 0
var completion_handled = false
var win_screen = WinCelebration.new()
var win_age = 0.0
var win_balance_before = 0
var coin_badge
var sound_enabled = true
var music_enabled = true
var vibration_enabled = true
var audio
var reduced_motion = false
var hint_bus = -1
var rejected_bus = -1
var blockers: Array = []
var reject_time = 0.0
var impact: Dictionary = {}
var impact_age = 1.0
var toast = ""
var toast_time = 0.0
var queue_slide = 0.0
var worker_position = WORKER_HOME
var worker_carry = -1
var worker_batch_count = 0
var batch_pickup = 0.0
var collecting = false
var worker_facing: float = 1.0
var worker_walking = false
var worker_lift = 0.0
var worker_idle_time = 0.0
var worker_panic_time = -1.0
var worker_idle_jump = 0.0
var truck_idle_time := 0.0
var horn_bus := -1
var horn_age := 1.0
var last_horn_bus := -1
var load_feedback: Array = []
var cargo_trips = 0
var confetti: Array = []
var sfx: AudioStreamPlayer
var notes: Dictionary = {}
var save_enabled = true
var save_path = SAVE_PATH
var speed_factor = 1.0
var automation = false
var style_cache: Dictionary = {}

func _ready() -> void:
	for icon in GAME_ICONS:
		game_icon_regions.append(Rect2(icon.get_image().get_used_rect()))
	font = preload("res://assets/fonts/MPLUSRounded1c-Medium.ttf")
	juicy_font = FontVariation.new()
	juicy_font.base_font = preload("res://assets/fonts/MPLUSRounded1c-Black.ttf")
	juicy_font.variation_embolden = 0.0
	art = Art.new(self,font)
	get_tree().quit_on_go_back = false
	Engine.max_fps = 60
	RenderingServer.set_default_clear_color(PAPER)
	Input.set_emulate_mouse_from_touch(true)
	Input.set_emulate_touch_from_mouse(false)
	sfx = AudioStreamPlayer.new()
	sfx.volume_db = -18.0
	add_child(sfx)
	_make_notes()
	var args = OS.get_cmdline_user_args()
	automation = automation or "--capture" in args or "--smoke-test" in args or "--demo" in args
	save_enabled = save_enabled and not automation
	if save_enabled:
		_load_save()
		daily_rewards.restore(economy.state.daily_calendar)
	audio = preload("res://scripts/game_audio.gd").new()
	add_child(audio)
	_sync_audio_preferences()
	_load_level(0 if automation else mini(unlocked,model.level_count()-1))
	road_menu = preload("res://scenes/menu/level_road_menu.tscn").instantiate()
	road_menu.visible = false
	add_child(road_menu)
	road_menu.size = get_viewport_rect().size
	get_viewport().size_changed.connect(func(): road_menu.size = get_viewport_rect().size)
	road_menu.level_selected.connect(_load_level)
	coin_badge = CoinBadge.new()
	coin_badge.position = Vector2(388,18)
	coin_badge.size = Vector2(134,44)
	add_child(coin_badge)
	modal_layer = CanvasLayer.new()
	modal_layer.layer = 20
	add_child(modal_layer)
	ads.simulate = "--fake-ads" in args
	store.simulate = "--fake-store" in args
	_sync_coins()
	road_menu.settings_requested.connect(_open_settings)
	road_menu.shop_requested.connect(func(): _open_shop(["road_menu"]))
	road_menu.resume_requested.connect(_resume_from_menu)
	road_menu.preference_changed.connect(_set_preference)
	if not automation:
		_show_road_menu(false)
		_open_daily_bonus.call_deferred()
	if "--capture" in args: _capture.call_deferred()
	if "--smoke-test" in args: _smoke_test.call_deferred()
	if "--demo" in args: _demo.call_deferred()

func _process(delta:float) -> void:
	_sync_modals()
	if overlay=="crane_preview" and crane_preview==null:
		crane_preview=preload("res://scripts/crane_offer.gd").new()
		add_child(crane_preview)
	if crane_preview: crane_preview.sync(self)
	for pop in slot_pops: pop.age += delta
	slot_pops = slot_pops.filter(func(pop): return pop.age<1.0)
	if reduced_motion:
		intro_delays.clear()
	if overlay == "" and not intro_delays.is_empty():
		intro_age += delta
		if intro_age >= 1.05: intro_delays.clear()
	_sync_audio_preferences()
	var modal_balance: bool = modal!=null and int(modal.spec.get("balance",-1))>=0
	coin_badge.visible = overlay in ["","win","stuck","crane_preview","tutorial"] and not modal_balance
	if road_menu: road_menu.coin_badge.visible = not modal_balance
	if overlay=="win":
		win_age += delta
		coin_badge.amount = WinCelebration.displayed_balance(win_balance_before,coins,win_age,reduced_motion)
	if overlay=="slot_offer": spotlight_time += delta
	if overlay not in ["settings","levels","road_menu","slot_offer"]:
		traffic.advance(self,delta)
		elapsed += delta
		toast_time = maxf(0,toast_time-delta)
		reject_time = maxf(0,reject_time-delta)
		impact_age += delta
		for i in range(load_feedback.size()-1,-1,-1):
			load_feedback[i].age += delta
			if load_feedback[i].age>0.8: load_feedback.remove_at(i)
		for particle in confetti:
			particle.position += particle.velocity*delta
			particle.rotation += delta*particle.spin
	_process_pending_dispatch()
	_update_worker_idle(delta)
	_update_truck_idle(delta)
	queue_redraw()

func _reset_truck_idle() -> void:
	truck_idle_time = 0.0
	horn_bus = -1
	horn_age = 1.0

func _update_truck_idle(delta:float) -> void:
	if overlay != "" or busy or loading or road_busy or not arrival_ids.is_empty():
		_reset_truck_idle()
		return
	horn_age += delta
	truck_idle_time += delta
	if truck_idle_time < 15.0: return
	truck_idle_time = 0.0
	var candidates:Array[int] = []
	for bus:Dictionary in model.buses:
		if bus.status == "yard" and model.can_dispatch(bus.id): candidates.append(bus.id)
	if candidates.is_empty(): return
	if candidates.size()>1: candidates.erase(last_horn_bus)
	horn_bus = candidates.pick_random()
	last_horn_bus = horn_bus
	horn_age = 0.0
	_sound_effect("horn")

# Idle performance owns no loading tweens and is cancelled before work starts.
func _reset_worker_idle() -> void:
	worker_idle_time = 0.0
	if worker_panic_time >= 0.0:
		worker_position = WORKER_HOME
		worker_walking = false
	worker_panic_time = -1.0
	worker_idle_jump = 0.0

func _update_worker_idle(delta:float) -> void:
	if overlay != "" or busy or road_busy or loading or collecting or worker_batch_count > 0 or worker_carry >= 0 or reduced_motion:
		_reset_worker_idle()
		return
	if worker_panic_time < 0.0:
		worker_idle_time += delta
		if worker_idle_time < 4.5: return
		worker_panic_time = maxf(0.0,worker_idle_time-4.5)
	else:
		worker_panic_time += delta
	var t:float = worker_panic_time
	var left := Vector2(24,WORKER_HOME.y)
	if t < 1.2:
		worker_facing = -1.0
		worker_position = WORKER_HOME.lerp(left,t/1.2)
		worker_walking = true
	elif t < 2.4:
		worker_facing = 1.0
		worker_position = left.lerp(WORKER_HOME,(t-1.2)/1.2)
		worker_walking = true
	elif t < 3.75:
		worker_position = WORKER_HOME
		worker_walking = false
		worker_idle_jump = sin(fmod(t-2.4,0.45)/0.45*PI)*17.0
	else:
		_reset_worker_idle()

func _notification(what:int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED,NOTIFICATION_APPLICATION_FOCUS_OUT]:
		if is_node_ready() and overlay == "" and not automation: _open_settings()
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_node_ready(): _back()

func _back() -> void:
	if modal != null:
		modal.back()
		return
	if overlay == "road_menu":
		if road_menu.can_resume: _resume_from_menu()
		return
	if overlay == "levels": overlay = levels_origin
	elif overlay == "slot_offer": _close_slot_offer()
	elif overlay == "rescue_menu": overlay = "stuck"
	elif overlay == "settings": _resume()
	elif overlay == "": _open_settings()

func _cancel_animation() -> void:
	_reset_truck_idle()
	intro_delays.clear()
	_reset_worker_idle()
	if audio:
		audio.stop_effects()
		audio.pause_effects(false)
	generation += 1
	traffic.routes.clear()
	arrival_ids.clear()
	for tween in [active_tween,motion_tween]:
		if tween and tween.is_valid():
			tween.kill()
			tween.finished.emit()
	active_tween = null
	motion_tween = null
	paused_tween = null
	paused_motion_tween = null
	road_busy = false
	pending_dispatch = -1
	loading = false
	busy = false

func _load_level(index:int) -> void:
	if index<0 or index>=model.level_count(): return
	if model.level_index==index and moves>0 and not completion_handled and not attempt_failed:
		economy.failure(index)
		_save()
	rescue_count = 0
	paid_slots = 0
	attempt_rescued = false
	attempt_failed = false
	tutorial_prompted = false
	slot_pops.clear()
	peak_bays = 0
	reward_details.clear()
	level_reward = 0
	reward_doubled = false
	win_age = 0.0
	_close_modal(true)
	_sync_coins()
	completion_handled = false
	menu_settings = false
	if road_menu: road_menu.hide()
	_cancel_animation()
	model.tablet_layout = get_viewport_rect().size.y/get_viewport_rect().size.x < 1.55
	ROAD_Y = 375.0 if model.tablet_layout else 516.0
	WALKWAY_Y = 365.0 if model.tablet_layout else 465.0
	model.load_level(index)
	if audio: audio.set_context("game")
	history.clear()
	moves = 0
	boarded = 0
	total_passengers = model.queue.size()
	busy = false
	overlay = ""
	confetti.clear()
	hint_bus = -1
	rejected_bus = -1
	impact.clear()
	impact_age = 1.0
	reject_time = 0
	queue_slide = 0
	toast_time = 0
	worker_position = WORKER_HOME
	worker_carry = -1
	worker_batch_count = 0
	batch_pickup = 0.0
	collecting = false
	worker_lift = 0
	worker_walking = false
	load_feedback.clear()
	cargo_trips = 0
	_sync_visuals()
	intro_age = 0.0
	if not reduced_motion:
		var ordered:Array = model.buses.duplicate()
		ordered.sort_custom(func(a,b): return a.position.y+a.position.x*0.3 < b.position.y+b.position.x*0.3)
		for i in ordered.size():
			intro_delays[ordered[i].id] = float(i)/maxi(1,ordered.size()-1)*0.5
	if index==0 and not automation and not bool(economy.state.get("intro_seen",false)): _start_tutorial.call_deferred(generation)


func _sync_visuals() -> void:
	bus_visuals.clear()
	for bus in model.buses:
		bus_visuals[bus.id] = {"position":bus.position if bus.status=="yard" else _bay_position(bus.bay,bus.kind),"angle":bus.angle if bus.status=="yard" else BAY_ANGLE,"scale":1.0}

func _yard_position(bus:Dictionary) -> Vector2:
	return bus.position

func _bay_position(bay:int,kind:int=0) -> Vector2:
	return _bay_front(bay)+_bay_back()*Model.LENGTHS[kind]*model.layout_scale*0.5

func _bay_front(bay:int) -> Vector2:
	return Vector2(BAY_X[clampi(bay,0,BAY_X.size()-1)],227)

func _bay_back() -> Vector2:
	return Vector2(-sin(BAY_ANGLE),cos(BAY_ANGLE))

func _bay_road(bay:int,y:float=ROAD_Y) -> Vector2:
	return _bay_front(bay)+_bay_back()*((y-_bay_front(bay).y)/cos(BAY_ANGLE))

func _belt_position(index:int) -> Vector2:
	return Vector2(468-index*BELT_STEP+queue_slide,133)

func _belt_cargo_scale(material_id:int) -> float:
	var size: Vector2 = Art.Cargo.draw_rect(material_id).size
	return minf(BELT_CARGO_SIZE.x/size.x,BELT_CARGO_SIZE.y/size.y)

func _belt_cargo_center(index:int) -> Vector2:
	var material_id: int = model.queue[index]
	var height: float = Art.Cargo.draw_rect(material_id).size.y*_belt_cargo_scale(material_id)
	return Vector2(_belt_position(index).x,BELT_BOTTOM-height*0.5)

func _duration(seconds:float) -> float:
	return seconds*(0.38 if reduced_motion else 1.0)*speed_factor

func _dispatch(id:int) -> void:
	_reset_truck_idle()
	# Input can interrupt the presentation without delaying a player's move.
	intro_delays.clear()
	_reset_worker_idle()
	if overlay != "": return
	if model.get_bus(id).is_empty() or model.get_bus(id).status!="yard": return
	blockers = model.blocking_ids(id)
	var maneuver:Array = []
	if not blockers.is_empty() and model.free_bay()>=0:
		maneuver = _maneuver_arrival(id)
	if not blockers.is_empty() and maneuver.is_empty():
		if road_busy or loading or not arrival_ids.is_empty():
			pending_dispatch = id
			return
		rejected_bus = id
		reject_time = 1.8
		await _blocked_bump(id)
		return
	if model.free_bay()<0:
		_message("Посты заняты — отмени ход или дождись погрузки")
		return
	var before = {"state":model.undo_snapshot(),"moves":moves,"boarded":boarded,"cargo_trips":cargo_trips,"dispatch_id":id}
	var start: Vector2 = bus_visuals[id].position
	var exit_point: Vector2 = model.exit_position(id)
	# Stop the checked forward sweep at the service road, before the loading bays.
	if exit_point.y<ROAD_Y:
		var direction: Vector2 = model.forward(model.get_bus(id))
		if direction.y< -0.001: exit_point = start+direction*((ROAD_Y-start.y)/direction.y)
	if not model.dispatch(id): return
	# Every accepted click is a separate move, including during other animations.
	history.append(before)
	busy = true
	arrival_ids[id] = true
	hint_bus = -1
	reject_time = 0
	moves += 1
	var ticket = generation
	var bus = model.get_bus(id)

	while road_busy or overlay!="":
		await get_tree().process_frame
		if ticket!=generation: return
	if not maneuver.is_empty(): maneuver=_maneuver_arrival(id,bus.bay)
	var planner = TruckRoute.new()
	planner.setup(self,id)
	var path:Array = maneuver if not maneuver.is_empty() else planner.plan(start,bus.angle,_bay_position(bus.bay,bus.kind),BAY_ANGLE)
	while path.is_empty() and not traffic.routes.is_empty():
		await get_tree().process_frame
		if ticket!=generation: return
		if not traffic.routes.is_empty(): continue
		planner.setup(self,id)
		path=planner.plan(start,bus.angle,_bay_position(bus.bay,bus.kind),BAY_ANGLE)
	if not path.is_empty():
		await _follow_route(id,path)
	else:
		push_warning("No smooth arrival route for level %d truck %d" % [model.level_index+1,id])
		# Keep the legacy fallback exclusive if no safe smooth route was found.
		while road_busy or not traffic.routes.is_empty():
			await get_tree().process_frame
			if ticket!=generation: return
		road_busy=true
		_sound_effect("start")
		await _fallback_arrival(id,exit_point,ticket)
		if ticket!=generation: return
		road_busy=false
	if ticket != generation: return

	while overlay in ["settings","levels","road_menu","slot_offer"]:
		await get_tree().process_frame
		if ticket!=generation: return
	if bus.status!="arriving": return
	model.arrive(id)
	arrival_ids.erase(id)
	await _settle(ticket)
	if ticket != generation: return
	_refresh_busy()

func _maneuver_arrival(id:int,reserved_bay:int=-1) -> Array:
	var candidates:Array = model.maneuver_paths(id)
	if candidates.is_empty(): return []
	var bus:Dictionary = model.buses[id]
	var planner = TruckRoute.new()
	planner.setup(self,id)
	var finish:Vector2 = _bay_position(model.free_bay() if reserved_bay<0 else reserved_bay,bus.kind)
	# Prefer the shortest complete connection; include docked trucks in this check.
	var checked:Array = []
	var best:Array = []
	var best_cost:float = INF
	for prefix:Array in candidates:
		var valid := true
		for i in range(1,prefix.size()):
			var a:Dictionary=prefix[i-1]
			var b:Dictionary=prefix[i]
			if not planner.clear_sweep(Vector3(a.position.x,a.position.y,a.angle-PI/2),Vector3(b.position.x,b.position.y,b.angle-PI/2)):
				valid=false
				break
		if not valid: continue
		checked.append(prefix)
		var last:Dictionary = prefix.back()
		var tail:Array = planner.direct_plan(last.position,last.angle,finish,BAY_ANGLE)
		if tail.is_empty(): continue
		var cost:float = last.distance+tail.back().distance
		if cost>=best_cost: continue
		best_cost=cost
		best=prefix.duplicate(true)
		for i in range(1,tail.size()):
			var pose:Dictionary=tail[i].duplicate()
			pose.distance+=last.distance
			best.append(pose)
	if best.is_empty():
		checked.sort_custom(func(a,b): return a.back().distance+a.back().position.distance_to(finish)<b.back().distance+b.back().position.distance_to(finish))
		for prefix:Array in checked:
			var last:Dictionary = prefix.back()
			var tail:Array = planner.plan(last.position,last.angle,finish,BAY_ANGLE)
			if tail.is_empty(): continue
			best=prefix.duplicate(true)
			for i in range(1,tail.size()):
				var pose:Dictionary=tail[i].duplicate()
				pose.distance+=last.distance
				best.append(pose)
			break
	return best

func _fallback_arrival(id:int,exit_point:Vector2,ticket:int) -> void:
	var bus:Dictionary = model.get_bus(id)
	var start:Vector2 = bus_visuals[id].position
	# Stay on the exact checked forward vector until the full body exits.
	await _drive(id,exit_point,clampf(start.distance_to(exit_point)/340.0,0.25,0.85),bus.angle)
	if ticket != generation: return
	# Follow the perimeter without an extra outward leg hidden by edge projection.
	var route: Array[Vector2] = []
	if exit_point.y < model.yard_rect.position.y:
		route.append(Vector2(exit_point.x,ROAD_Y))
	elif exit_point.y > model.yard_rect.end.y:
		route.append(Vector2(exit_point.x,1220))
		route.append(Vector2(680,1220))
		route.append(Vector2(680,ROAD_Y))
	elif exit_point.x < model.yard_rect.position.x:
		route.append(Vector2(exit_point.x,ROAD_Y))
	elif exit_point.x > model.yard_rect.end.x:
		route.append(Vector2(exit_point.x,ROAD_Y))
	else:
		route.append(Vector2(exit_point.x,1220))
		route.append(Vector2(680,1220))
		route.append(Vector2(680,ROAD_Y))
	for point in route:
		var distance = Vector2(bus_visuals[id].position).distance_to(point)
		if distance < 1: continue
		var segment: Vector2 = point-Vector2(bus_visuals[id].position)
		var heading: float = bus_visuals[id].angle
		var forward := Vector2(sin(heading),-cos(heading))
		# A short reverse adjustment needs no 180-degree pivot.
		var travel_angle: float = heading if absf(segment.normalized().cross(forward)) < 0.001 else INF
		await _drive(id,point,clampf(distance/650.0,0.14,0.70),travel_angle)
		if ticket != generation: return
	await _drive(id,_bay_road(bus.bay),0.50)
	if ticket != generation: return
	# Turn into the bay while approaching, without a separate stationary pivot.
	_sound_effect("skid")
	await _drive(id,_bay_position(bus.bay,bus.kind),0.55,BAY_ANGLE)
	if ticket != generation: return

func _departure_route(id:int) -> Array:
	var planner = TruckRoute.new()
	planner.setup(self,id,true)
	var forward_planner = TruckRoute.new()
	forward_planner.setup(self,id)
	var visual:Dictionary = bus_visuals[id]
	var best:Array = []
	var best_length := INF
	for distance in [0.0,40.0,80.0,120.0,160.0,200.0,240.0,280.0]:
		var anchor:Vector2 = visual.position+_bay_back()*distance
		var prefix:Array=[]
		if distance>0:
			prefix=planner.direct_plan(visual.position,visual.angle,anchor,visual.angle)
			if prefix.is_empty(): continue
		for side in [8.0,532.0]:
			for y in ([330.0,350.0,375.0] if model.tablet_layout else [420.0,465.0,516.0]):
				if distance+anchor.distance_to(Vector2(side,y))>=best_length: continue
				var target_angle:float = -PI/2 if side<270 else PI/2
				var candidate:Array = forward_planner.direct_plan(anchor,visual.angle,Vector2(side,y),target_angle)
				if not candidate.is_empty() and candidate.back().distance+distance<best_length:
					best = prefix.duplicate(true)
					if not best.is_empty(): best.back().gear_change = true
					for pose:Dictionary in candidate:
						var shifted:Dictionary=pose.duplicate()
						shifted.distance+=distance
						if best.is_empty() or shifted.distance>best.back().distance+0.001: best.append(shifted)
					best_length = best.back().distance

	return best

func _follow_route(id:int,path:Array) -> void:
	var ticket:int = generation
	bus_visuals[id].route = true
	if model.buses[id].status=="arriving":
		while not traffic.reserve(self,id,path):
			await get_tree().process_frame
			if ticket!=generation:return
			if traffic.routes.is_empty():
				var planner=TruckRoute.new()
				planner.setup(self,id)
				path=planner.plan(bus_visuals[id].position,bus_visuals[id].angle,_bay_position(model.buses[id].bay,model.buses[id].kind),BAY_ANGLE)
				if path.is_empty():
					push_warning("Arrival could not find a safe route")
					var bus:Dictionary=model.buses[id]
					model.bays[bus.bay]=-1
					bus.bay=-1
					bus.status="yard"
					arrival_ids.erase(id)
					moves-=1
					_discard_failed_dispatch(id)
					_message("Проезд занят — попробуй после проезда соседней машины")
					_refresh_busy()
					return
		while traffic.routes.has(id):
			await get_tree().process_frame
			if ticket!=generation:return
		return
	var length:float = path.back().distance
	motion_tween = create_tween().set_trans(Tween.TRANS_LINEAR)
	var update_pose = func(distance:float):
		var low:=0
		var high:int=path.size()-1
		while high-low>1:
			var mid:int=(low+high)/2
			if path[mid].distance<distance: low=mid
			else: high=mid
		var weight:float=clampf(inverse_lerp(path[low].distance,path[high].distance,distance),0,1)
		bus_visuals[id].position=Vector2(path[low].position).lerp(path[high].position,weight)
		bus_visuals[id].angle=lerp_angle(path[low].angle,path[high].angle,weight)
	var change := -1.0
	for pose:Dictionary in path:
		if pose.get("gear_change",false): change=pose.distance
	if change>0 and change<length:
		var brake:float=minf(24.0,change)
		var accelerate:float=minf(24.0,length-change)
		if change>brake:
			motion_tween.tween_method(update_pose,0.0,change-brake,_duration((change-brake)/420.0))
		motion_tween.tween_method(update_pose,change-brake,change,_duration(brake/210.0)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		motion_tween.tween_method(update_pose,change,change+accelerate,_duration(accelerate/210.0)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		if change+accelerate<length:
			motion_tween.tween_method(update_pose,change+accelerate,length,_duration((length-change-accelerate)/420.0))
	else:
		motion_tween.tween_method(update_pose,0.0,length,_duration(maxf(0.06,length/420.0)))
	await motion_tween.finished
	if ticket!=generation: return
	motion_tween=null

func _blocked_bump(id:int) -> void:
	if blockers.is_empty(): return
	var hit:Dictionary = Contact.contact(model,id)
	if hit.is_empty(): return
	var ticket = generation
	var start:Vector2 = bus_visuals[id].position
	var direction:Vector2 = model.forward(model.get_bus(id))
	var angle:float = bus_visuals[id].angle
	hint_bus = -1
	road_busy = true
	busy = true
	await _drive(id,start+direction*hit.distance,clampf(hit.distance/420.0,0.16,0.65),angle)
	if ticket != generation: return
	impact = hit
	impact_age = 0.0
	_sound_effect("bump")
	_vibrate(45)
	# Retreat from visible contact without overshooting into a vehicle behind us.
	await _drive(id,start,0.32,angle)
	if ticket != generation: return
	bus_visuals[id].position = start
	road_busy = false
	_refresh_busy()

func _refresh_busy() -> void:
	busy = road_busy or loading or not arrival_ids.is_empty()
	if not busy and overlay == "": _check_end()

static func _drive_pose(start:Vector2,end:Vector2,initial:float,target:float,t:float,road_y:float=516.0) -> Dictionary:
	# Travel and steering share one clock; only steering eases, never every leg.
	var turn_fraction: float = clampf(42.0/maxf(start.distance_to(end),1.0),0.12,0.65)
	# Align quickly in the road's free space before entering a narrow loading bay.
	if is_equal_approx(start.y,road_y) and end.y<road_y and is_equal_approx(target,BAY_ANGLE):
		turn_fraction = minf(turn_fraction,6.0/maxf(start.distance_to(end),1.0))
	var steering: float = smoothstep(0.0,turn_fraction,t)
	var point: Vector2 = start.lerp(end,t)
	var delta := end-start
	if delta.length()>1.0 and absf(angle_difference(initial,target))>0.001:
		var direction := delta.normalized()
		var tangent := Vector2(sin(initial),-cos(initial))
		if tangent.dot(direction)<0: tangent = -tangent
		var u: float = clampf(t/turn_fraction,0.0,1.0)
		var bend: Vector2 = (tangent-direction)*delta.length()*turn_fraction*u*(1.0-u)*(1.0-u)
		# Keep road turns above the packed yard, including the longest trucks.
		if is_equal_approx(start.y,road_y) and is_equal_approx(end.y,road_y): bend.y = minf(bend.y,0.0)
		point += bend
	return {"position":point,"angle":lerp_angle(initial,target,steering)}

func _drive(id:int,end:Vector2,seconds:float,angle:float=INF) -> void:
	var ticket = generation
	var start: Vector2 = bus_visuals[id].position
	var initial: float = bus_visuals[id].angle
	var delta := end-start
	var target_angle: float = angle if is_finite(angle) else atan2(delta.x,-delta.y)
	if delta.length_squared()<0.01 and absf(angle_difference(initial,target_angle))<0.001: return
	# Parameterize by the visible path, removing time spent on clipped outer legs.
	var size: Vector2 = model.vehicle_size(model.get_bus(id))
	var table: Array[Vector2] = [Vector2.ZERO]
	var previous: Vector2 = EdgeRoute.position_for(start,initial,size)
	var previous_angle: float = initial
	var length: float = 0.0
	for sample in range(1,121):
		var t: float = sample/120.0
		var pose: Dictionary = _drive_pose(start,end,initial,target_angle,t,ROAD_Y)
		var point: Vector2 = EdgeRoute.position_for(pose.position,pose.angle,size)
		var turn_distance: float = absf(angle_difference(previous_angle,pose.angle))*size.y*0.12
		var step: float = sqrt(previous.distance_squared_to(point)+turn_distance*turn_distance)
		length += step
		if step>0.0001: table.append(Vector2(length,t))
		else: table[table.size()-1].y = t
		previous = point
		previous_angle = pose.angle
	if length<0.001:
		bus_visuals[id].position = end
		bus_visuals[id].angle = target_angle
		return
	var bump: bool = model.get_bus(id).status=="yard"
	var duration: float = seconds if bump else maxf(0.06,length/420.0)
	motion_tween = create_tween().set_trans(Tween.TRANS_SINE if bump else Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
	motion_tween.tween_method(func(progress:float):
		var distance: float = progress*length
		var low: int = 0
		var high: int = table.size()-1
		while high-low>1:
			var middle: int = (low+high)/2
			if table[middle].x<distance: low = middle
			else: high = middle
		var weight: float = inverse_lerp(table[low].x,table[high].x,distance)
		var t: float = lerpf(table[low].y,table[high].y,clampf(weight,0.0,1.0))
		var pose: Dictionary = _drive_pose(start,end,initial,target_angle,t,ROAD_Y)
		bus_visuals[id].position = pose.position
		bus_visuals[id].angle = pose.angle,
		0.0,1.0,_duration(duration))
	await motion_tween.finished
	if ticket != generation: return
	motion_tween = null

func _walk(end:Vector2,seconds:float) -> void:
	if absf(end.x-worker_position.x)>0.1: worker_facing = signf(end.x-worker_position.x)
	worker_walking = true
	active_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	active_tween.tween_property(self,"worker_position",end,_duration(seconds))
	await active_tween.finished
	active_tween = null
	worker_walking = false

func _settle(ticket:int) -> void:
	_reset_worker_idle()
	if loading: return
	loading = true
	busy = true
	while ticket == generation:
		var id = model.next_boarding()
		if id < 0: break
		var bus = model.get_bus(id)
		var material_id: int = model.queue[0]
		var batch_count: int = model.batch_size(id)
		assert(batch_count>0,"A loading trip must have a valid cargo batch")
		worker_carry = material_id
		worker_batch_count = 0
		queue_slide = 0.0
		# Reserve the unchanged queue, but walk to and stop at EACH physical item.
		# Cargo is committed only after the complete batch reaches the truck.
		for item in batch_count:
			var pickup_spot = _belt_position(item)+Vector2(0,52)
			await _walk(pickup_spot,clampf(worker_position.distance_to(pickup_spot)/360.0,0.16,0.55))
			if ticket != generation: return
			batch_pickup = 0.0
			collecting = true
			active_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			active_tween.tween_property(self,"batch_pickup",1.0,_duration(0.24))
			await active_tween.finished
			active_tween = null
			if ticket != generation: return
			worker_batch_count += 1
			if sound_enabled and not automation: audio.pickup(material_id)
			collecting = false
			batch_pickup = 0.0
		# The next run rolls along the conveyor while the collected stack stays held.
		active_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		active_tween.tween_property(self,"queue_slide",BELT_STEP*batch_count,_duration(0.25))
		await active_tween.finished
		active_tween = null
		if ticket != generation: return
		# Use the clear pedestrian edge and load from the rear of the vehicle.
		var rear = _bay_front(bus.bay)+_bay_back()*(Model.LENGTHS[bus.kind]*model.layout_scale+23)
		await _walk(Vector2(24,185),0.43)
		if ticket != generation: return
		await _walk(Vector2(24,WALKWAY_Y),0.40)
		if ticket != generation: return
		await _walk(_bay_road(bus.bay,WALKWAY_Y),0.48)
		if ticket != generation: return
		await _walk(rear,0.23)
		if ticket != generation: return
		active_tween = create_tween()
		active_tween.tween_property(self,"worker_lift",1.0,_duration(0.20))
		await active_tween.finished
		active_tween = null
		if ticket != generation: return
		var committed: bool = model.board_batch(id,batch_count)
		assert(committed,"Cargo batch must commit atomically at its reserved truck")
		if not committed: return
		boarded += batch_count
		cargo_trips += 1
		load_feedback.append({"position":rear,"count":batch_count,"age":0.0})
		worker_carry = -1
		worker_batch_count = 0
		batch_pickup = 0.0
		queue_slide = 0.0
		worker_lift = 0
		if sound_enabled and not automation: audio.deposit(batch_count)
		if model.get_bus(id).status == "leaving":
			_sound_effect("full")
			_vibrate(25)
		await _walk(_bay_road(bus.bay,WALKWAY_Y),0.23)
		if ticket != generation: return
		await _walk(Vector2(24,WALKWAY_Y),0.48)
		if ticket != generation: return
		await _walk(Vector2(24,185),0.40)
		if ticket != generation: return
		await _walk(WORKER_HOME,0.43)
		if ticket != generation: return
		if model.get_bus(id).status == "leaving":
			# Arrivals may drive while the worker loads; share the road for departures.
			while road_busy or not arrival_ids.is_empty() or overlay in ["settings","levels","road_menu","slot_offer"]:
				await get_tree().process_frame
				if ticket != generation: return
			road_busy = true
			_sound_effect("start")

			var path:Array = _departure_route(id)
			if not path.is_empty():
				await _follow_route(id,path)
			else:
				push_warning("No smooth departure route for level %d truck %d" % [model.level_index+1,id])
				bus_visuals[id].route = false
				await _drive(id,_bay_road(bus.bay),0.55,BAY_ANGLE)
				if ticket != generation: return
				await _drive(id,Vector2(680,ROAD_Y),0.65,PI/2)
			if ticket != generation: return

			model.depart(id)
			road_busy = false
	loading = false
	peak_bays = maxi(peak_bays,model.open_bay_count-model.bays.slice(0,model.open_bay_count).count(-1))
	_refresh_busy()

func _check_end() -> void:
	if model.is_won():
		if completion_handled: return
		completion_handled = true
		win_balance_before = coins
		level_reward = _claim_level_reward(model.level_index)
		win_age = 0.0
		if coin_badge: coin_badge.amount = WinCelebration.displayed_balance(win_balance_before,coins,win_age,reduced_motion)
		overlay = "win"
		unlocked = maxi(unlocked,mini(model.level_index+1,model.level_count()-1))
		_save()
		_play("win")

	elif model.is_stuck():
		overlay = "stuck"
		if _free_tutorial_slot() and not tutorial_prompted:
			tutorial_prompted = true
			_open_slot_offer(model.open_bay_count)


func _claim_level_reward(index:int) -> int:
	if index in rewarded_levels: return 0
	rewarded_levels.append(index)
	reward_details = economy.completion(index,rewarded_levels.size(),total_passengers,attempt_rescued,peak_bays,model.open_bay_count)
	var amount: int = reward_details.total
	coins += amount
	_sync_coins()
	return amount

func _free_tutorial_slot() -> bool:
	return model.level_index>=SlotOffer.TUTORIAL_LEVEL and not bool(economy.state.tutorial_done) and model.open_bay_count==3

func _slot_price() -> int:
	if _free_tutorial_slot() or int(economy.state.inventory.get("extra_slot",0))>0: return 0
	return SlotOffer.PRICE

func _sync_coins() -> void:
	if coin_badge: coin_badge.amount = coins
	if road_menu: road_menu.coin_badge.amount = coins

func _discard_failed_dispatch(id:int) -> void:
	# A reserved move can still fail to find a route. Remove it from history
	# and repair later checkpoints, so Undo cannot resurrect that reservation.
	var found := false
	for i in range(history.size()-1,-1,-1):
		if int(history[i].get("dispatch_id",-1)) == id:
			history.remove_at(i)
			for j in range(i,history.size()):
				var state:Dictionary = history[j].state
				var truck:Dictionary = state.buses[id]
				if truck.bay >= 0: state.bays[truck.bay] = -1
				truck.bay = -1
				truck.status = "yard"
				history[j].moves -= 1
			found = true
			break
	if found: bus_visuals[id] = {"position":model.buses[id].position,"angle":model.buses[id].angle,"scale":1.0}

func _undo() -> void:
	if busy or history.is_empty(): return
	var previous = history.back()
	if model.restore(previous.state):
		history.pop_back()
		_cancel_animation()
		moves = previous.moves
		boarded = previous.boarded
		cargo_trips = previous.get("cargo_trips",0)
		load_feedback.clear()
		overlay = ""
		hint_bus = -1
		reject_time = 0
		worker_position = WORKER_HOME
		worker_carry = -1
		worker_batch_count = 0
		worker_lift = 0.0
		worker_walking = false
		collecting = false
		batch_pickup = 0.0
		queue_slide = 0.0
		_sync_visuals()
		_message("Машины и конвейер вернулись на ход назад")
		var ticket:int = generation
		await _settle(ticket)
		if ticket == generation: _refresh_busy()

func _hint() -> void:
	if busy: return
	hint_bus = model.find_hint()
	if hint_bus == -3: _message("Освободи машину у края или отмени последний ход")
	elif hint_bus < 0: _message("Вернись на ход назад — здесь нет решения")
	else: _message("Выделенная машина поможет разгрузить двор")

func _open_settings() -> void:
	if audio: audio.pause_effects(true)
	if road_menu and road_menu.visible:
		menu_settings = true
		road_menu.hide()
	overlay = "settings"
	if active_tween and active_tween.is_valid() and active_tween.is_running():
		paused_tween = active_tween
		paused_tween.pause()
	if motion_tween and motion_tween.is_valid() and motion_tween.is_running():
		paused_motion_tween = motion_tween
		paused_motion_tween.pause()

func _resume() -> void:
	if menu_settings:
		menu_settings = false
		_show_road_menu(road_menu.can_resume)
		return
	overlay = ""
	if audio:
		audio.pause_effects(false)
		audio.set_context("game")
	if paused_tween and paused_tween.is_valid(): paused_tween.play()
	if paused_motion_tween and paused_motion_tween.is_valid(): paused_motion_tween.play()
	paused_tween = null
	paused_motion_tween = null

func _message(value:String) -> void:
	if modal!=null:
		modal.flash(value)
		return
	toast = value
	toast_time = 3.0

func _input(event:InputEvent) -> void:
	if daily_screen!=null:
		if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE: daily_screen.closed.emit()
		return
	if modal!=null:
		if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE: modal.back()
		return
	if (event is InputEventMouseButton or event is InputEventKey or event is InputEventScreenTouch) and event.pressed:
		_reset_truck_idle()
		_reset_worker_idle()
	if overlay == "road_menu":
		if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE: _back()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE: _back()
	if not (event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT): return
	var p: Vector2 = get_global_transform_with_canvas().affine_inverse()*event.position
	var world_p:Vector2 = _world_transform().affine_inverse()*p
	if overlay=="":
		for bay in range(model.open_bay_count,Model.BAY_COUNT):
			if world_p.distance_to(_cone_position(bay))<36:
				_tap_cone(bay)
				return
	if overlay != "":
		_overlay_input(_panel_transform().affine_inverse()*p)
		return
	if Rect2(143,_footer_y()-27,54,54).has_point(p): _undo()
	elif Rect2(243,_footer_y()-27,54,54).has_point(p): _hint()
	elif Rect2(343,_footer_y()-27,54,54).has_point(p): _show_road_menu(true)
	else:
		var candidate := _truck_at(world_p)
		if candidate >= 0:
			if audio: audio.effect("touch")
			_dispatch(candidate)

func _truck_at(point:Vector2) -> int:
	var candidate := -1
	var nearest := INF
	for bus:Dictionary in model.buses:
		if bus.status!="yard": continue
		var visual:Dictionary = bus_visuals[bus.id]
		var center:Vector2 = EdgeRoute.position_for(visual.position,visual.angle,model.vehicle_size(bus))
		var local:Vector2 = (point-center).rotated(-visual.angle)
		var size:Vector2 = model.vehicle_size(bus)
		if Rect2(-size/2,size).grow(6).has_point(local):
			var distance:float = point.distance_squared_to(center)
			if distance<nearest:
				candidate = bus.id
				nearest = distance
	return candidate

func _process_pending_dispatch() -> void:
	if pending_dispatch<0 or road_busy or loading or not arrival_ids.is_empty() or overlay!="": return
	var id := pending_dispatch
	pending_dispatch = -1
	_dispatch(id)

func _overlay_input(p:Vector2) -> void:
	if overlay == "rescue_menu":
		if Rect2(415,234,50,50).has_point(p): overlay = "stuck"
		for i in 3:
			if Rect2(76,350+i*90,388,60).has_point(p): _purchase_rescue(["crane","swap","shuffle"][i])
		return
	if overlay == "slot_offer":
		if Rect2(478,18,44,44).has_point(p): _close_slot_offer()
		elif (_world_transform().affine_inverse()*(_panel_transform()*p)).distance_to(_cone_position(model.open_bay_count))<58:
			offered_bay = model.open_bay_count
			_purchase_slot()
		elif not _free_tutorial_slot() and Rect2(76,550,388,58).has_point(p):
			offered_bay = model.open_bay_count
			_purchase_slot()
	elif overlay == "settings":
		if Rect2(415,234,50,50).has_point(p): _resume()
		elif Rect2(76,352,388,54).has_point(p):
			_set_preference("sound",not sound_enabled)
		elif Rect2(76,426,388,54).has_point(p):
			reduced_motion = not reduced_motion
			_save()
		elif Rect2(76,516,388,58).has_point(p): _resume()
		elif Rect2(76,590,388,58).has_point(p): _load_level(model.level_index)
		elif Rect2(76,663,388,50).has_point(p):
			levels_origin = "settings"
			_show_road_menu(true)
	elif overlay == "levels":
		if Rect2(415,234,50,50).has_point(p): overlay = levels_origin
		for i in model.level_count():
			if Rect2(83+(i%3)*129,350+floori(i/3.0)*117,116,98).has_point(p) and i <= unlocked: _load_level(i)
	elif overlay == "win":
		if WinCelebration.DOUBLE.has_point(p): _open_double_offer()
		elif WinCelebration.NEXT.has_point(p):
			if model.level_index+1 < model.level_count(): _load_level(model.level_index+1)
			else:
				levels_origin = "win"
				_show_road_menu(false)
		elif WinCelebration.REPLAY.has_point(p): _load_level(model.level_index)

func _cone_position(bay:int) -> Vector2:
	return _bay_front(bay)+_bay_back()*43.0

func _open_rescue_menu() -> void:
	if busy or rescue_count>=int(economy.config.rescue.max_tools): return
	overlay = "rescue_menu"

func _rescue_price(tool:String) -> int:
	if int(economy.state.inventory.get(tool,0))>0: return 0
	return int(economy.config.rescue.get(tool+"_cost",0))

func _rescue_target() -> int:
	if model.queue.is_empty(): return -1
	var target := -1
	for bus: Dictionary in model.buses:
		if bus.status=="yard" and bus.color==model.queue[0]:
			if target<0 or bus.capacity>model.buses[target].capacity: target = bus.id
	return target

func _can_rescue(tool:String) -> bool:
	if busy or not model.is_stuck() or rescue_count>=int(economy.config.rescue.max_tools): return false
	if tool=="shuffle": return not Boosters.docked_trucks(model).is_empty() and model.queue.size()>1
	if not bool(economy.config.rescue.get(tool+"_enabled",false)): return false
	if _rescue_target()<0: return false
	if tool=="crane": return model.open_bay_count<Model.BAY_COUNT
	return model.bays.count(-1)<Model.BAY_COUNT

func _purchase_rescue(tool:String) -> void:
	if overlay not in ["rescue_menu","stuck"] or not _can_rescue(tool): return
	var price := _rescue_price(tool)
	if coins<price: return
	var ticket: int = generation
	var target := _rescue_target()
	var returning := -1
	var bay := -1
	if tool=="swap":
		for id: int in model.bays:
			if id>=0 and (returning<0 or model.buses[id].load<model.buses[returning].load): returning = id
		if returning<0: return
		bay = model.buses[returning].bay
	elif tool=="crane": bay = model.open_bay_count
	coins -= price
	if price==0: economy.state.inventory[tool] = maxi(0,int(economy.state.inventory.get(tool,0))-1)
	rescue_count += 1
	attempt_rescued = true
	history.clear() # Paid tools are not refundable or repeatable through Undo.
	_sync_coins()
	_save()
	overlay = ""
	busy = true
	road_busy = true
	if tool=="shuffle":
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		model.queue = Boosters.smart_shuffle(model.queue,rng,0,Boosters.docked_trucks(model),int(economy.config.rescue.shuffle_strength))
	else:
		if tool=="crane": model.unlock_next_bay()
		if returning>=0:
			var old: Dictionary = model.buses[returning]
			for unit in int(old.load): model.queue.append(old.color)
			boarded -= int(old.load)
			old.load = 0
			old.status = "yard"
			old.bay = -1
			await _airlift(returning,old.position,old.angle)
			if ticket!=generation: return
		var bus: Dictionary = model.buses[target]
		model.bays[bay] = target
		bus.bay = bay
		bus.status = "arriving"
		await _airlift(target,_bay_position(bay,bus.kind),BAY_ANGLE)
		if ticket!=generation: return
		model.arrive(target)
	road_busy = false
	await _settle(ticket)
	if ticket==generation: _refresh_busy()

func _airlift(id:int,end:Vector2,angle:float) -> void:
	var start: Vector2 = bus_visuals[id].position
	var initial: float = bus_visuals[id].angle
	motion_tween = create_tween()
	motion_tween.tween_method(func(t:float):
		bus_visuals[id].position = start.lerp(end,smoothstep(0.0,1.0,t))
		bus_visuals[id].angle = lerp_angle(initial,angle,smoothstep(0.0,1.0,t))
		bus_visuals[id].lift = sin(PI*t),0.0,1.0,_duration(0.8))
	await motion_tween.finished
	motion_tween = null

func _open_slot_offer(bay:int) -> void:
	if bay<model.open_bay_count or bay>=Model.BAY_COUNT: return
	if bay!=model.open_bay_count:
		_message("Сначала открой соседнее место")
		return
	if not _free_tutorial_slot():
		offered_bay = bay
		_purchase_slot()
		return
	slot_return_overlay = overlay
	_open_settings()
	offered_bay = bay
	spotlight_time = 0.0
	overlay = "slot_offer"

func _close_slot_offer() -> void:
	_resume()
	overlay = slot_return_overlay
	offered_bay = -1

func _purchase_slot(by_ad:bool=false) -> void:
	if offered_bay!=model.open_bay_count: return
	var tutorial: bool = _free_tutorial_slot()
	var price: int = 0 if by_ad else _slot_price()
	if not tutorial and coins<price:
		_message("Нужно %d монет" % price)
		return
	if not tutorial and rescue_count>=int(economy.config.rescue.max_tools):
		_message("Лимит помощи в этой попытке исчерпан")
		return
	var pop_position: Vector2 = _cone_position(offered_bay)
	if not model.unlock_next_bay(): return
	if tutorial: economy.state.tutorial_done = true
	else:
		coins -= price
		if price==0 and not by_ad: economy.state.inventory.extra_slot=int(economy.state.inventory.extra_slot)-1
		paid_slots += 1
	rescue_count += 1
	attempt_rescued = true
	history.clear()
	_sync_coins()
	_save()
	if overlay=="slot_offer":
		slot_return_overlay = ""
		_close_slot_offer()
	else:
		offered_bay = -1
		if overlay in ["stuck","rescue_menu"]: _resume()
	if not tutorial: slot_pops.append({"position":pop_position,"age":0.0})

func _show_road_menu(resumable:bool=true) -> void:
	_sync_coins()
	if not road_menu: return
	if overlay == "": _open_settings()
	menu_settings = false
	overlay = "road_menu"
	road_menu.configure(model.level_count(),unlocked,reduced_motion,resumable)
	road_menu.resume_level = model.level_index if resumable else -1
	road_menu.sync_preferences(music_enabled,sound_enabled,vibration_enabled)
	if audio: audio.set_context("menu")
	road_menu.show()

func _resume_from_menu() -> void:
	road_menu.hide()
	menu_settings = false
	_resume()
	if not busy: _check_end() # Back from the map onto a dead end reopens its window.

func _draw() -> void:
	if overlay == "road_menu": return
	if art == null: return
	_draw_space(Transform2D.IDENTITY)
	draw_rect(get_viewport_rect(),PAPER)
	var source_scale:float = 1179.0/540.0
	# Keep the factory facade and belt full width; its functional apron shares
	# the exact same transform as vehicles, bays, routes and hit testing.
	draw_texture_rect_region(FACTORY,Rect2(0,0,540,Layout.SPLIT),Rect2(0,0,1179,Layout.SPLIT*source_scale))
	if _world_transform().get_scale().x < 0.999:
		draw_line(Vector2(0,Layout.SPLIT),Vector2(540,Layout.SPLIT),Color("81838c"),5)
		draw_line(Vector2(0,Layout.SPLIT+2),Vector2(540,Layout.SPLIT+2),Color("ffcf37"),2)
	_draw_conveyor()
	_draw_space(_world_transform())
	if _world_transform().get_scale().x >= 0.999:
		draw_texture_rect_region(FACTORY,Rect2(0,Layout.SPLIT,540,809.0/source_scale-Layout.SPLIT),Rect2(0,Layout.SPLIT*source_scale,1179,809.0-Layout.SPLIT*source_scale))
	else:
		for bay in Model.BAY_COUNT:
			art_transform(_bay_front(bay),BAY_ANGLE)
			_round(Rect2(-30,0,60,151),Color("5f657a"),5)
			art_transform(Vector2.ZERO)
	_draw_loading()
	_draw_yard()
	for bus in model.buses:
		if bus.status in ["yard","docked"]: _draw_truck(bus)
	for bus in model.buses:
		if bus.status in ["arriving","leaving"]: _draw_truck(bus)
	_draw_impact()
	var world:Transform2D = _world_transform()
	var blend:float = smoothstep(Layout.SPLIT,Layout.SPLIT+65.0,worker_position.y)
	_draw_space(Transform2D.IDENTITY.interpolate_with(world,blend))
	var visible_carry = worker_carry if worker_batch_count>0 else -1
	art.worker(worker_position+Vector2(-worker_lift*7,-worker_lift*5-worker_idle_jump),visible_carry,worker_walking and not reduced_motion,elapsed*(32 if worker_panic_time>=0 else 19),worker_batch_count,worker_panic_time>=0,worker_facing,collecting)
	if collecting:
		var a = _belt_cargo_center(worker_batch_count)
		var b = worker_position+Vector2(0,-17)
		var p = a.bezier_interpolate(a+Vector2(0,12),b+Vector2(14,-22),b,batch_pickup)
		art.material(p,worker_carry,lerpf(_belt_cargo_scale(worker_carry),0.58,batch_pickup))
	_draw_space(world)
	for feedback in load_feedback:
		var pos: Vector2 = feedback.position+Vector2(0,-feedback.age*22)
		_round(Rect2(pos-Vector2(20,13),Vector2(40,24)),Color("127f49"),9)
		_text("+%d" % feedback.count,pos+Vector2(0,5),15,Color.WHITE,true)
	for pop in slot_pops:
		SlotOffer.draw_pop(self,pop.position,pop.age,reduced_motion)
	_draw_space(Transform2D.IDENTITY)
	_draw_header()
	_draw_footer()
	if toast_time>0 and overlay=="":
		_round(Rect2(25,_footer_y()-63,490,31),INK,10)
		_text(toast,Vector2(270,_footer_y()-42),12,Color.WHITE,true)
	if overlay!="" and overlay not in ["stuck","tutorial"]:
		if overlay!="slot_offer": draw_rect(get_viewport_rect(),Color(0.055,0.10,0.20,0.88) if overlay in ["win","stuck","crane_preview"] else Color(0.12,0.20,0.24,0.47))
		_draw_space(_panel_transform())
		_draw_overlay()
	_draw_space(Transform2D.IDENTITY)

func _draw_header() -> void:
	_round(Rect2(18,18,126,40),Color("172737"),13)
	_text("УРОВЕНЬ %d" % (model.level_index+1),Vector2(81,44),16,Color.WHITE,true)
	_round(Rect2(18,64,126,6),Color("233345"),3)
	if boarded>0: _round(Rect2(18,64,maxf(6,126.0*boarded/maxi(1,total_passengers)),6),ACCENT,3)

func _draw_conveyor() -> void:
	for i in range(worker_batch_count,mini(model.queue.size(),worker_batch_count+14)):
		if collecting and i==worker_batch_count: continue
		var p = _belt_position(i)
		if p.x>=123 and p.x<=489:
			art.material(_belt_cargo_center(i),model.queue[i],_belt_cargo_scale(model.queue[i]))

func _draw_loading() -> void:
	for bay in range(model.open_bay_count,Model.BAY_COUNT):
		SlotOffer.draw_cone(self,_cone_position(bay))
	# The five painted angled places are part of the supplied factory artwork.
	# A small meter is visible only for an occupied loading bay.
	for i in model.bays.size():
		if model.bays[i]<0: continue
		var parked: Dictionary = model.get_bus(model.bays[i])
		if parked.status not in ["docked","leaving"]: continue
		var p = _bay_front(i)+Vector2(0,-18)
		_round(Rect2(p-Vector2(17,8),Vector2(34,16)),INK,6)
		_text("%d/%d" % [parked.load,parked.capacity],p+Vector2(0,4),11,Color.WHITE,true)

func _draw_yard() -> void:
	if hint_bus>=0:
		var bus = model.get_bus(hint_bus)
		var size: Vector2 = model.vehicle_size(bus)
		var p: Vector2 = bus.position+model.forward(bus)*(size.y/2+11)
		draw_circle(p,4,Color("fffaf0"))

func _draw_impact() -> void:
	if impact.is_empty() or impact_age>0.48: return
	var progress:float = impact_age/0.48
	var normal:Vector2 = -impact.direction
	var tangent := Vector2(-normal.y,normal.x)
	# Two short ripples on either side of the actual contact, outside the touching body.
	for side in [-1,1]:
		for ring in 2:
			var center:Vector2 = impact.point+tangent*side*(8.0+progress*12.0+ring*5.0)
			var curve := PackedVector2Array()
			for step in 9:
				var t:float = step/8.0
				curve.append(center+normal*(t-0.5)*12.0+tangent*side*sin(t*PI)*3.5)
			draw_polyline(curve,Color(1.0,0.97,0.80,(1.0-progress)*0.95),1.25,true)

func _draw_truck(bus:Dictionary) -> void:
	var visual: Dictionary = bus_visuals[bus.id]
	var rejected = false
	var selected = hint_bus==bus.id or pending_dispatch==bus.id
	var visible_position: Vector2 = visual.position if visual.get("route",false) else EdgeRoute.position_for(visual.position,visual.angle,model.vehicle_size(bus))
	var lift: float = visual.get("lift",0.0)
	if lift>0.01:
		draw_line(visible_position+Vector2(0,-150),visible_position+Vector2(0,-25),Color("ffce35"),3.0,true)
	var intro_scale := 1.0
	var intro_height := 0.0
	if intro_delays.has(bus.id) and bus.status == "yard":
		var t:float = intro_age-float(intro_delays[bus.id])
		if t <= 0.0: return
		if t < 0.28:
			var p:float = t/0.28
			intro_scale = lerpf(0.05,1.06,1.0-pow(1.0-p,3.0))
			intro_height = 18.0*pow(1.0-p,2.0)
		elif t < 0.52:
			var p:float = (t-0.28)/0.24
			intro_scale = 1.0+0.06*cos(p*PI*1.5)*(1.0-p)
			intro_height = sin(p*PI)*3.0
	var sway := 0.0
	if bus.id == horn_bus and bus.status == "yard" and horn_age < 0.85 and not reduced_motion:
		var p:float = horn_age/0.85
		sway = sin(p*TAU*2.0)*deg_to_rad(2.0)*sin(p*PI)
	art.vehicle(bus,visible_position-Vector2(0,lift*30+intro_height),visual.angle+sway,(1.0+lift*0.12)*intro_scale*model.layout_scale,selected,rejected)

func _draw_footer() -> void:
	# Leave the lower service lane visible behind the three controls.
	for i in GAME_ICONS.size():
		var center := Vector2(170+i*100,_footer_y())
		var enabled: bool = i==2 or (not busy and (i!=0 or not history.is_empty()))
		var region: Rect2 = game_icon_regions[i]
		var fit: float = minf(54.0/region.size.x,54.0/region.size.y)
		var drawn: Vector2 = region.size*fit
		var tint := Color(1,1,1,1.0 if enabled else 0.4)
		draw_texture_rect_region(GAME_ICONS[i],Rect2(center-drawn*0.5,drawn),region,tint)

func _juicy_text(value:String,y:float,text_size:int,tint:Color) -> void:
	var actual_size: int = text_size
	while juicy_font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,actual_size).x>470:
		actual_size -= 1
	var width: float = juicy_font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,actual_size).x
	var pos := Vector2(270-width/2,y)
	draw_string_outline(juicy_font,pos+Vector2(0,5),value,HORIZONTAL_ALIGNMENT_LEFT,-1,actual_size,10,Color("08182e"))
	draw_string_outline(juicy_font,pos,value,HORIZONTAL_ALIGNMENT_LEFT,-1,actual_size,7,Color("132d50"))
	draw_string(juicy_font,pos,value,HORIZONTAL_ALIGNMENT_LEFT,-1,actual_size,tint)

func _draw_slot_spotlight() -> void:
	var center:Vector2 = _panel_transform().affine_inverse()*(_world_transform()*(_cone_position(model.open_bay_count)+Vector2(0,-2)))
	var pulse: float = 0.5 if reduced_motion else (sin(spotlight_time*TAU/1.4)+1.0)*0.5
	var radii := Vector2(48,66)
	# A real opening in the dim layer keeps both the cone and its painted bay bright.
	for i in 96:
		var a := Vector2.from_angle(TAU*i/96.0)
		var b := Vector2.from_angle(TAU*(i+1)/96.0)
		draw_colored_polygon(PackedVector2Array([center+a*radii,center+b*radii,center+b*2000,center+a*2000]),Color(0.025,0.065,0.15,0.81))
	art_transform(center,0,Vector2(1,66.0/48.0))
	for ring in range(9,0,-1):
		draw_arc(Vector2.ZERO,48+ring*1.7+pulse*3,0,TAU,96,Color(1.0,0.76,0.12,(0.02+0.025*pulse)*(1.0-ring/12.0)),3,true)
	draw_arc(Vector2.ZERO,49+pulse*2,0,TAU,96,Color(1.0,0.88,0.35,0.55+0.35*pulse),2.5,true)
	art_transform(Vector2.ZERO)
	var arrow_side:float = -1.0 if get_viewport_rect().size.y<1000 else 1.0
	var arrow_y: float = center.y+arrow_side*(91+(0.0 if reduced_motion else pulse*7))
	var tip := Vector2(center.x,arrow_y)
	draw_line(tip+Vector2(0,40*arrow_side),tip,Color("122b4a"),13,true)
	draw_line(tip+Vector2(0,40*arrow_side),tip,Color("ffe04d"),8,true)
	var arrow := PackedVector2Array([tip+Vector2(-13,14*arrow_side),tip,tip+Vector2(13,14*arrow_side)])
	draw_polyline(arrow,Color("122b4a"),13,true)
	draw_polyline(arrow,Color("ffe04d"),8,true)
	if _free_tutorial_slot():
		_juicy_text("НАЖМИ НА КОНУС",475,37,Color.WHITE)
		_juicy_text("ОТКРОЙ МЕСТО!",529,43,Color.WHITE)
		_juicy_text("БЕСПЛАТНО!",593,49,Color("ffe04d"))
		_text("До конца этой попытки",Vector2(270,635),23,Color.WHITE,true)
	else:
		_juicy_text("БОЛЬШЕ МЕСТА!",475,43,Color("ffe04d"))
		_text("Открой место до конца попытки",Vector2(270,512),22,Color.WHITE,true)
		var price: int = _slot_price()
		_button(Rect2(76,550,388,58),"Открыть за %d монет" % price if price>0 else "Цена уточняется",true,price>0 and coins>=price)
		_button(Rect2(76,625,388,58),"Реклама пока недоступна",false,false)
	for sign_value in [-1,1]:
		draw_line(Vector2(491,30+sign_value*9),Vector2(509,30-sign_value*9),Color.WHITE,4,true)

func _draw_overlay() -> void:
	if overlay=="crane_preview":
		preload("res://scripts/crane_offer.gd").draw_crane(self)
		return
	if overlay=="win":
		win_screen.draw(self,win_age,level_reward,_panel_transform().affine_inverse()*(coin_badge.position+Vector2(24,coin_badge.size.y*0.5)),reduced_motion,model.level_index==model.level_count()-1)
		return
	if overlay=="slot_offer":
		_draw_slot_spotlight()
		return
	_round(Rect2(52,224,436,515),Color("ffffff"),30)
	if overlay=="rescue_menu":
		_text("Помощь на стройке",Vector2(270,291),27,INK,true)
		_close_icon()
		var labels := ["Кран", "Замена машины", "Перемешать грузы"]
		var keys := ["crane", "swap", "shuffle"]
		for i in 3:
			var price := _rescue_price(keys[i])
			_button(Rect2(76,350+i*90,388,60),"%s · %d монет" % [labels[i],price],true,_can_rescue(keys[i]) and coins>=price)
		_text("Помощь действует в этой попытке",Vector2(270,654),17,MUTED,true)
		_text("Баланс: %d" % coins,Vector2(270,689),18,INK,true)
	elif overlay=="settings":
		_text("Перерыв на стройке",Vector2(270,291),27,INK,true)
		_text("Груз и машины подождут",Vector2(270,320),15,MUTED,true)
		_close_icon()
		_setting_row(352,"Звуки погрузки",sound_enabled)
		_setting_row(426,"Меньше анимации",reduced_motion)
		_button(Rect2(76,516,388,58),"Продолжить работу",true)
		_button(Rect2(76,590,388,58),"Начать уровень заново",false)
		_text("Выбрать склад",Vector2(270,695),16,INK,true)
	elif overlay=="levels":
		_text("Твои склады",Vector2(270,291),29,INK,true)
		_text("Больше машин — интереснее задача",Vector2(270,320),14,MUTED,true)
		_close_icon()
		for i in model.level_count():
			var rect = Rect2(83+(i%3)*129,350+floori(i/3.0)*117,116,98)
			_round(rect,ACCENT if i<=unlocked else Color("e5eae6"),18)
			_text("%02d" % (i+1),rect.position+Vector2(58,49),29,INK if i<=unlocked else MUTED,true)
			_text("НАЧАТЬ" if i<=unlocked else "ЗАКРЫТ",rect.position+Vector2(58,77),10,INK if i<=unlocked else MUTED,true)
		_text("Новый склад открывается после полной отгрузки",Vector2(270,642),12,MUTED,true)

func _close_icon() -> void:
	for s in [-1,1]: draw_line(Vector2(431,249+s*6),Vector2(443,249-s*6),MUTED,2,true)

func _setting_row(y:float,label:String,enabled:bool) -> void:
	_round(Rect2(76,y,388,54),Color("edf1e9"),15)
	_text(label,Vector2(95,y+34),16,INK)
	_round(Rect2(391,y+13,52,28),ACCENT if enabled else Color("c6d1c7"),14)
	draw_circle(Vector2(429 if enabled else 405,y+27),10,Color.WHITE)

func _button(rect:Rect2,label:String,primary:bool,enabled:bool=true,icon:String="") -> void:
	var base = ACCENT if primary else Color("d9e3f2")
	if not enabled: base = Color("e0e7f0")
	_round(Rect2(rect.position+Vector2(0,3),rect.size),base.darkened(0.09),18)
	_round(rect,base,18)
	var color = INK if enabled else Color("8293a8")
	var center = rect.get_center()
	if icon=="": _text(label,center+Vector2(0,6),17,color,true)
	else:
		_text(label,center+Vector2(9,5),14,color,true)
		var ic = center+Vector2(-49,0)
		if icon=="hint":
			draw_arc(ic+Vector2(0,-2),6,0,TAU,20,color,1.7,true)
			draw_line(ic+Vector2(-3,7),ic+Vector2(3,7),color,2,true)
		else:
			draw_arc(ic,7,-PI*0.8,PI*0.8,20,color,1.7,true)
			draw_line(ic+Vector2(-7,-7),ic+Vector2(-7,0),color,2,true)
			draw_line(ic+Vector2(-7,0),ic+Vector2(-1,0),color,2,true)

func _round(rect:Rect2,color:Color,radius:int=12,_fill:bool=true,border:Color=Color.TRANSPARENT,border_width:int=0) -> void:
	var key = "%s:%d:%s:%d" % [color.to_html(),radius,border.to_html(),border_width]
	if not style_cache.has(key):
		var style = StyleBoxFlat.new()
		style.bg_color = color
		style.set_corner_radius_all(radius)
		style.border_color = border
		style.set_border_width_all(border_width)
		style.anti_aliasing = true
		style_cache[key] = style
	draw_style_box(style_cache[key],rect)

func _text(value:String,pos:Vector2,size:int,color:Color,center:bool=false,right:bool=false) -> void:
	var width = font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
	var offset = width*0.5 if center else (width if right else 0.0)
	draw_string(font,pos-Vector2(offset,0),value,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)

func _load_save() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(save_path)!=OK: return
	unlocked = clampi(int(cfg.get_value("game","unlocked",0)),0,model.level_count()-1)
	coins = maxi(0,int(cfg.get_value("economy","coins",economy.config.start_balance)))
	economy.restore(cfg.get_value("economy","state",{}))
	rewarded_levels.clear()
	for index in cfg.get_value("economy","rewarded_levels",[]):
		if index is int and index>=0 and index not in rewarded_levels: rewarded_levels.append(index)
	_sync_coins()
	sound_enabled = bool(cfg.get_value("settings","sound",true))
	music_enabled = bool(cfg.get_value("settings","music",true))
	vibration_enabled = bool(cfg.get_value("settings","vibration",true))
	reduced_motion = bool(cfg.get_value("settings","reduced_motion",false))

func _save() -> void:
	if not save_enabled: return
	var cfg = ConfigFile.new()
	cfg.set_value("game","unlocked",unlocked)
	cfg.set_value("economy","coins",coins)
	cfg.set_value("economy","state",economy.state)
	cfg.set_value("economy","rewarded_levels",rewarded_levels)
	cfg.set_value("settings","sound",sound_enabled)
	cfg.set_value("settings","music",music_enabled)
	cfg.set_value("settings","vibration",vibration_enabled)
	cfg.set_value("settings","reduced_motion",reduced_motion)
	if cfg.save(save_path)!=OK: push_warning("Progress could not be saved")

func _set_preference(key:String,enabled:bool) -> void:
	match key:
		"music": music_enabled = enabled
		"sound":
			sound_enabled = enabled
			if not enabled: sfx.stop()
		"vibration": vibration_enabled = enabled
	_sync_audio_preferences()
	if road_menu: road_menu.sync_preferences(music_enabled,sound_enabled,vibration_enabled)
	_save()
	if key=="vibration" and enabled: _vibrate(20)

func _sync_audio_preferences() -> void:
	if not audio: return
	var want_music = music_enabled and not automation
	var want_effects = sound_enabled and not automation
	if audio.music_enabled!=want_music or audio.effects_enabled!=want_effects:
		audio.set_preferences(want_music,want_effects)

func _sound_effect(key:String) -> void:
	if sound_enabled and not automation and audio: audio.effect(key)

func _vibrate(milliseconds:int) -> void:
	if vibration_enabled and not automation: Input.vibrate_handheld(milliseconds)

func _make_notes() -> void:
	for key in ["move","board","leave","win"]:
		var frequency = {"move":190.0,"board":570.0,"leave":380.0,"win":760.0}[key]
		var data = PackedByteArray()
		var count = 6615 if key=="win" else 2205
		data.resize(count*2)
		for i in count:
			var t = float(i)/22050.0
			var envelope = sin(PI*float(i)/count)*0.24
			data.encode_s16(i*2,int(sin(TAU*frequency*t)*envelope*32767))
		var stream = AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = 22050
		stream.data = data
		notes[key] = stream

func _play(key:String) -> void:
	if sound_enabled:
		sfx.stream = notes[key]
		sfx.play()

func _capture() -> void:
	_load_level(4)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/factory-layout-preview.png")
	print("CARGO_CAPTURE_SAVED")
	get_tree().quit()

func _smoke_test() -> void:
	sound_enabled = false
	speed_factor = 0.015
	for index in model.level_count():
		_load_level(index)
		var guard = 0
		while not model.is_won() and guard<40:
			var id = model.find_hint()
			assert(id>=0,"Cargo UI smoke: no solving move")
			if id<0:
				get_tree().quit(1)
				return
			await _dispatch(id)
			guard += 1
		assert(model.is_won(),"Cargo UI smoke: level not completed")
		assert(boarded==total_passengers,"Cargo UI smoke: cargo count differs")
		print("CARGO_UI_LEVEL_%d_PASS" % (index+1))
	_load_level(0)
	var id = model.find_hint()
	await _dispatch(id)
	_undo()
	assert(model.get_bus(id).status=="yard" and moves==0 and boarded==0)
	print("CARGO_UI_UNDO_PASS")
	print("CARGO_UI_ALL_PASS")
	get_tree().quit()

func _demo() -> void:
	sound_enabled = false
	speed_factor = 0.70
	_load_level(3)
	await get_tree().create_timer(0.7).timeout
	for bus in model.buses:
		if not model.blocking_ids(bus.id).is_empty():
			_dispatch(bus.id)
			break
	await get_tree().create_timer(1.0).timeout
	for i in 5:
		var id = model.find_hint()
		if id>=0: await _dispatch(id)
		if i==1:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://artifacts/factory-layout-loading.png")
	await get_tree().create_timer(0.5).timeout
	print("CARGO_DEMO_COMPLETE")
	get_tree().quit()


func _open_daily_bonus() -> void:
	if not save_enabled or daily_screen!=null:return
	var date=Time.get_date_dict_from_system()
	var day:int=int(Time.get_unix_time_from_datetime_dict(date)/86400)
	var info:Dictionary=daily_rewards.calendar.visit(day)
	economy.state.daily_calendar=daily_rewards.calendar.state.duplicate(true)
	_save()
	if not info.can_claim:
		_maybe_show_season()
		return
	road_menu.hide()
	daily_screen=preload("res://scripts/daily_bonus.gd").new()
	daily_screen.sound_enabled=sound_enabled
	add_child(daily_screen)
	daily_screen.z_index=100
	daily_screen.size=get_viewport_rect().size
	get_viewport().size_changed.connect(_resize_daily_bonus)
	daily_screen.configure(daily_rewards.definitions(),info.cards)
	daily_screen.closed.connect(func():
		get_viewport().size_changed.disconnect(_resize_daily_bonus)
		daily_screen.queue_free()
		daily_screen=null
		road_menu.show()
		_maybe_show_season())
	var result:Dictionary=daily_rewards.claim(day,economy.state.inventory)
	if result.index>=0:
		coins+=int(result.coins)
		economy.state.daily_calendar=daily_rewards.calendar.state.duplicate(true)
		_save()
		_sync_coins()
		daily_screen.reveal(result.index)

func _resize_daily_bonus():
	if daily_screen!=null:daily_screen.size=get_viewport_rect().size

# ------------------------------------------------------------------ modal windows
# Specs come from scripts/ui/modal_catalog.gd; this section only routes actions.
# A modal lives while `overlay` stays in its scope, so every existing transition
# (undo, restart, menu, win) closes it without extra bookkeeping.

func _open_modal(spec:Dictionary,handler:Callable,scope:Array) -> void:
	_close_modal(true)
	var opened: Control = GameModal.new(spec)
	opened.reduced_motion = reduced_motion
	opened.action.connect(handler)
	opened.tapped.connect(func():
		_sound_effect("touch")
		_vibrate(12))
	opened.closed.connect(func(): if modal==opened: modal = null)
	modal = opened
	modal_scope = scope
	modal_layer.add_child(opened)

func _close_modal(instant:bool=false) -> void:
	if modal==null: return
	if instant:
		modal.queue_free()
		modal = null
	else: modal.close()

func _sync_modals() -> void:
	if modal_layer==null: return
	if modal!=null and not modal.is_closing() and overlay not in modal_scope: modal.close()
	if overlay=="stuck" and modal==null and daily_screen==null: _open_modal(Modals.stuck(_stuck_context()),_on_stuck_action,["stuck"])

func _modal_is(id:String) -> bool:
	return modal!=null and not modal.is_closing() and modal.spec.get("id","")==id

func _stuck_context() -> Dictionary:
	return {
		"coins":coins,
		"slot_available":model.open_bay_count<Model.BAY_COUNT,
		"slot_price":_slot_price(),
		"ad_ready":ads.is_ready() and bool(economy.config.rewarded_video.get("rescue",false)),
		"undo_price":UNDO_PRICE,
		"undo_gifts":int(economy.state.inventory.get("undo",0)),
		"can_undo":not history.is_empty(),
		"can_shuffle":_can_rescue("shuffle"),
		"shuffle_price":_rescue_price("shuffle"),
		"can_crane":_can_rescue("crane"),
		"crane_price":_rescue_price("crane"),
		"rescue_left":rescue_count<int(economy.config.rescue.max_tools),
	}

func _on_stuck_action(id:String) -> void:
	match id:
		"slot_coins":
			if coins<_slot_price():
				_open_shortfall(_slot_price(),["stuck"])
				return
			_open_slot_offer(model.open_bay_count)
		"slot_ad":
			_watch_ad(id,func():
				offered_bay = model.open_bay_count
				_purchase_slot(true))
		"undo": _paid_undo()
		"shuffle","crane":
			if coins<_rescue_price(id):
				_open_shortfall(_rescue_price(id),["stuck"])
				return
			_purchase_rescue(id)
		"retry": _load_level(model.level_index)
		"menu": _show_road_menu(true)
	if _modal_is("stuck") and overlay=="stuck": modal.update_spec(Modals.stuck(_stuck_context()))

func _paid_undo() -> void:
	if history.is_empty():
		_message("Нет хода для отмены")
		return
	var gifts := int(economy.state.inventory.get("undo",0))
	if gifts==0 and coins<UNDO_PRICE:
		_open_shortfall(UNDO_PRICE,[overlay])
		return
	var before := history.size()
	_undo()
	if history.size()<before:
		if gifts>0: economy.state.inventory.undo = gifts-1
		else: coins -= UNDO_PRICE
		_sync_coins()
		_save()

## A paid cone asks first instead of charging on a stray tap.
func _tap_cone(bay:int) -> void:
	var price := _slot_price()
	if bay!=model.open_bay_count or price==0:
		_open_slot_offer(bay)
		return
	var scope := [overlay]
	_open_modal(Modals.offer("extra_slot",price,coins,ads.is_ready()),func(id:String):
		match id:
			"buy":
				if coins<price:
					_open_shortfall(price,scope)
					return
				_close_modal()
				_open_slot_offer(bay)
			"watch_ad":
				_watch_ad(id,func():
					_close_modal()
					offered_bay = model.open_bay_count
					_purchase_slot(true))
			"close": _close_modal()
	,scope)

func _open_shortfall(need:int,scope:Array) -> void:
	var ad_coins := int(economy.config.rewarded_video.get("coins",25))
	var pack_id: String = store.pack_for(need-coins)
	var pack := {}
	if pack_id!="": pack = {"coins":int(store.product(pack_id).contents.coins),"price":store.price(pack_id)}
	_open_modal(Modals.shortfall(need,coins,ad_coins,ads.is_ready(),pack),func(id:String):
		match id:
			"buy_pack": _buy(pack_id,id)
			"shop": _open_shop(scope)
			"watch_ad":
				_watch_ad(id,func():
					coins += ad_coins
					_sync_coins()
					_save()
					if modal: modal.update_spec(Modals.ad_reward("done",ad_coins,coins)))
			"close": _close_modal()
	,scope)

func _open_double_offer() -> void:
	if level_reward<=0 or reward_doubled or not ads.is_ready(): return
	if model.level_index+1<int(economy.config.rewarded_video.get("double_unlock_level",1)): return
	var amount: int = level_reward
	_open_modal(Modals.double_reward(amount,coins,true),func(id:String):
		match id:
			"watch_ad":
				_watch_ad(id,func():
					reward_doubled = true
					coins += amount
					_sync_coins()
					_save()
					if modal: modal.update_spec(Modals.ad_reward("done",amount,coins)))
			"close": _close_modal()
	,["win"])

## Plays a rewarded video for the pressed button; the reward runs only after a
## finished video.
func _watch_ad(id:String,reward:Callable) -> void:
	if not ads.is_ready():
		_message("Ролик пока не готов — попробуй позже")
		return
	var shown := modal
	if shown: shown.set_busy(id,true)
	if audio: audio.pause_effects(true)
	var finished: bool = await ads.show_rewarded()
	if audio: audio.pause_effects(false)
	if is_instance_valid(shown): shown.set_busy(id,false)
	if finished: reward.call()
	else: _message("Ролик не досмотрен — награды нет")

## `ticket` is the level generation that asked for it; a reload cancels it.
func _start_tutorial(ticket:int) -> void:
	await get_tree().create_timer(0.1 if reduced_motion else 1.1).timeout
	if ticket!=generation or overlay!="" or moves>0 or model.level_index!=0 or modal!=null: return
	overlay = "tutorial"
	tutorial_step = 0
	_show_tutorial_step()

func _show_tutorial_step() -> void:
	var spot := {}
	if tutorial_step==0:
		var id: int = model.find_hint()
		if id>=0:
			var bus: Dictionary = model.buses[id]
			var center: Vector2 = EdgeRoute.position_for(bus.position,bus.angle,model.vehicle_size(bus))
			spot = {"center":_world_transform()*center,"radius":74.0*_world_transform().get_scale().x}
	elif tutorial_step==1:
		spot = {"center":Vector2(306,122),"radius":96.0}
	var spec := Modals.tutorial(tutorial_step,spot)
	if _modal_is("tutorial"): modal.update_spec(spec)
	else: _open_modal(spec,_on_tutorial_action,["tutorial"])

func _on_tutorial_action(id:String) -> void:
	if id=="tutorial_next" and tutorial_step<Modals.TUTORIAL_STEPS.size()-1:
		tutorial_step += 1
		_show_tutorial_step()
		return
	economy.state.intro_seen = true
	_save()
	overlay = ""

func _maybe_show_season() -> void:
	if automation or modal!=null or daily_screen!=null: return
	var now := int(Time.get_unix_time_from_system())
	var event := Modals.active_event(Modals.load_events(),now)
	if event.is_empty() or event.get("product","") in economy.state.purchases: return
	var day := now/86400
	var seen: Dictionary = economy.state.season_seen
	if int(seen.get(event.id,-1))==day: return
	seen[event.id] = day
	_save()
	_open_modal(Modals.seasonal(event,store),func(id:String):
		match id:
			"buy_bundle": _buy(event.product,id)
			"close": _close_modal()
	,["road_menu"])

func _open_shop(scope:Array) -> void:
	var ad_coins := int(economy.config.rewarded_video.get("coins",25))
	var spec_now := func() -> Dictionary:
		return Modals.shop({"coins":coins,"store":store,"owned":economy.state.purchases,
			"event":Modals.active_event(Modals.load_events(),int(Time.get_unix_time_from_system())),
			"ad_ready":ads.is_ready(),"ad_coins":ad_coins})
	_open_modal(spec_now.call(),func(id:String):
		if id.begins_with("buy:"):
			_buy(id.substr(4),id)
			return
		match id:
			"free_coins":
				_watch_ad(id,func():
					coins += ad_coins
					_sync_coins()
					_save()
					if _modal_is("shop"):
						modal.update_spec(spec_now.call())
						modal.flash("+%d %s" % [ad_coins,Modals.coin_word(ad_coins)]))
			"restore": _message("Покупки появятся в следующей версии" if not store.is_available() else "Покупки восстановлены")
			"close": _close_modal()
	,scope)

## Buys a store product for real money; contents arrive only after the store
## confirms. `button` shows the loading state on the pressed control.
func _buy(product_id:String,button:String) -> void:
	if not store.is_available():
		_message("Покупки появятся в следующей версии")
		return
	var product: Dictionary = store.product(product_id)
	if product.is_empty() or product_id in economy.state.purchases: return
	var shown := modal
	if shown: shown.set_busy(button,true)
	var paid: bool = await store.purchase(product_id)
	if is_instance_valid(shown): shown.set_busy(button,false)
	if not paid:
		_message("Покупка не завершена — деньги не списаны")
		return
	for key: String in product.contents:
		if key=="coins": coins += int(product.contents.coins)
		else: economy.state.inventory[key] = int(economy.state.inventory.get(key,0))+int(product.contents[key])
	if product.get("once",false): economy.state.purchases.append(product_id)
	_sync_coins()
	_save()
	if modal: modal.update_spec(Modals.received(product.contents,coins))
