extends Node2D

const Model = preload("res://scripts/game_model.gd")
const Contact = preload("res://scripts/collision_feedback.gd")
const Art = preload("res://scripts/cargo_art.gd")
const CoinBadge = preload("res://scripts/coin_badge.gd")
const COMPLETION_REWARD = 20
const INK = Color("152b46")
const MUTED = Color("536780")
const PAPER = Color("b2b0b6")
const FACTORY = preload("res://assets/artwork/cargo/Background-factory.png")
const GAME_ICONS = [
	preload("res://assets/artwork/menu/undo.png"),
	preload("res://assets/artwork/menu/bulb.png"),
	preload("res://assets/artwork/menu/door-back.png")
]
var game_icon_regions: Array[Rect2] = []
const ACCENT = Color("ffc400")
const BAY_X = [87.0, 164.0, 240.0, 316.0, 393.0]
const BAY_ANGLE = -27.0 * PI / 180.0
const ROAD_Y = 510.0
const WALKWAY_Y = 465.0
const BELT_STEP = 60.0
const BELT_BOTTOM = 315.0*540.0/1179.0 # Lower edge of the moving belt in the original artwork.
const BELT_CARGO_SIZE = Vector2(115,130)*540.0/1179.0
const WORKER_HOME = Vector2(468,185)
const SAVE_PATH = "user://cargo_yard.cfg"

var model = Model.new()
var art
var font: Font
var bus_visuals: Dictionary = {}
var history: Array = []
var busy = false
var road_busy = false
var loading = false
var motion_tween: Tween
var paused_motion_tween: Tween
var overlay = ""
var levels_origin = "settings"
var road_menu
var menu_settings = false
var elapsed = 0.0
var active_tween: Tween
var paused_tween: Tween
var generation = 0
var boarded = 0
var total_passengers = 0 # Cargo units; retained for regression test compatibility.
var moves = 0
var unlocked = 0
var coins = 0
var rewarded_levels: Array[int] = []
var level_reward = 0
var completion_handled = false
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
var worker_walking = false
var worker_lift = 0.0
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
	font = ThemeDB.fallback_font
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
	automation = "--capture" in args or "--smoke-test" in args or "--demo" in args
	save_enabled = not automation
	if save_enabled: _load_save()
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
	_sync_coins()
	road_menu.settings_requested.connect(_open_settings)
	road_menu.resume_requested.connect(_resume_from_menu)
	road_menu.preference_changed.connect(_set_preference)
	if not automation: _show_road_menu(false)
	if "--capture" in args: _capture.call_deferred()
	if "--smoke-test" in args: _smoke_test.call_deferred()
	if "--demo" in args: _demo.call_deferred()

func _process(delta:float) -> void:
	_sync_audio_preferences()
	coin_badge.visible = overlay == ""
	if overlay not in ["settings","levels","road_menu"]:
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
	queue_redraw()

func _notification(what:int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED,NOTIFICATION_APPLICATION_FOCUS_OUT]:
		if is_node_ready() and overlay == "" and not automation: _open_settings()
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_node_ready(): _back()

func _back() -> void:
	if overlay == "road_menu":
		if road_menu.can_resume: _resume_from_menu()
		return
	if overlay == "levels": overlay = levels_origin
	elif overlay == "settings": _resume()
	elif overlay == "": _open_settings()

func _cancel_animation() -> void:
	if audio:
		audio.stop_effects()
		audio.pause_effects(false)
	generation += 1
	for tween in [active_tween,motion_tween]:
		if tween and tween.is_valid():
			tween.kill()
			tween.finished.emit()
	active_tween = null
	motion_tween = null
	paused_tween = null
	paused_motion_tween = null
	road_busy = false
	loading = false
	busy = false

func _load_level(index:int) -> void:
	level_reward = 0
	completion_handled = false
	menu_settings = false
	if road_menu: road_menu.hide()
	_cancel_animation()
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

func _sync_visuals() -> void:
	bus_visuals.clear()
	for bus in model.buses:
		bus_visuals[bus.id] = {"position":bus.position if bus.status=="yard" else _bay_position(bus.bay,bus.kind),"angle":bus.angle if bus.status=="yard" else BAY_ANGLE,"scale":1.0}

func _yard_position(bus:Dictionary) -> Vector2:
	return bus.position

func _bay_position(bay:int,kind:int=0) -> Vector2:
	return _bay_front(bay)+_bay_back()*Model.LENGTHS[kind]*0.5

func _bay_front(bay:int) -> Vector2:
	return Vector2(BAY_X[clampi(bay,0,BAY_X.size()-1)],247)

func _bay_back() -> Vector2:
	return Vector2(-sin(BAY_ANGLE),cos(BAY_ANGLE))

func _bay_road(bay:int,y:float=ROAD_Y) -> Vector2:
	return _bay_front(bay)+_bay_back()*((y-247.0)/cos(BAY_ANGLE))

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
	if road_busy or overlay != "": return
	if not model.can_dispatch(id):
		if not -1 in model.bays:
			_message("Посты заняты — отмени ход или дождись погрузки")
		else:
			blockers = model.blocking_ids(id)
			rejected_bus = id
			reject_time = 1.8
			await _blocked_bump(id)
		return
	var before = {"state":model.snapshot(),"moves":moves,"boarded":boarded,"cargo_trips":cargo_trips}
	var start: Vector2 = bus_visuals[id].position
	var exit_point: Vector2 = model.exit_position(id)
	if not model.dispatch(id): return
	# Overlapping calls form one undo group, captured before any cargo is reserved.
	if not busy: history.append(before)
	busy = true
	road_busy = true
	hint_bus = -1
	reject_time = 0
	moves += 1
	var ticket = generation
	var bus = model.get_bus(id)

	# Stay on the exact checked forward vector until the full body exits.
	await _drive(id,exit_point,clampf(start.distance_to(exit_point)/340.0,0.25,0.85),bus.angle)
	if ticket != generation: return
	# Clear the yard, then pivot on the spot before each straight segment.
	var route: Array[Vector2] = []
	if exit_point.y < Model.YARD_RECT.position.y:
		route.append(Vector2(exit_point.x,ROAD_Y))
	elif exit_point.x < Model.YARD_RECT.position.x:
		route.append(Vector2(-140,exit_point.y))
		route.append(Vector2(-140,ROAD_Y))
	elif exit_point.x > Model.YARD_RECT.end.x:
		route.append(Vector2(680,exit_point.y))
		route.append(Vector2(680,ROAD_Y))
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
	# Finish turning on the clear road, then enter the painted bay on its axis.
	await _drive(id,_bay_road(bus.bay),0.22,BAY_ANGLE)
	if ticket != generation: return
	await _drive(id,_bay_position(bus.bay,bus.kind),0.55,BAY_ANGLE)
	if ticket != generation: return
	model.arrive(id)
	road_busy = false
	await _settle(ticket)
	if ticket != generation: return
	_refresh_busy()

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
	busy = road_busy or loading
	if not busy and overlay == "": _check_end()

func _drive(id:int,end:Vector2,seconds:float,angle:float=INF) -> void:
	var ticket = generation
	var start: Vector2 = bus_visuals[id].position
	var initial: float = bus_visuals[id].angle
	var delta = end-start
	var target_angle = angle if is_finite(angle) else atan2(delta.x,-delta.y)
	# Rotation and translation never overlap: a compact pivot, then straight travel.
	if absf(angle_difference(initial,target_angle)) > 0.001:
		motion_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		motion_tween.tween_method(func(t:float): bus_visuals[id].angle = lerp_angle(initial,target_angle,t),0.0,1.0,_duration(0.18))
		await motion_tween.finished
		if ticket != generation: return
		motion_tween = null
	if delta.length_squared() < 0.01: return
	motion_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	motion_tween.tween_method(func(t:float): bus_visuals[id].position = start.lerp(end,t),0.0,1.0,_duration(seconds*0.82))
	await motion_tween.finished
	if ticket != generation: return
	motion_tween = null

func _walk(end:Vector2,seconds:float) -> void:
	worker_walking = true
	active_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	active_tween.tween_property(self,"worker_position",end,_duration(seconds))
	await active_tween.finished
	active_tween = null
	worker_walking = false

func _settle(ticket:int) -> void:
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
		var rear = _bay_front(bus.bay)+_bay_back()*(Model.LENGTHS[bus.kind]+23)
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
			while road_busy or overlay in ["settings","levels","road_menu"]:
				await get_tree().process_frame
				if ticket != generation: return
			road_busy = true

			# Reverse out along the bay markings before turning onto the road.
			await _drive(id,_bay_road(bus.bay),0.55,BAY_ANGLE)
			if ticket != generation: return
			await _drive(id,_bay_road(bus.bay),0.22,PI/2)
			if ticket != generation: return
			await _drive(id,Vector2(680,ROAD_Y),0.65,PI/2)
			if ticket != generation: return
			model.depart(id)
			road_busy = false
	loading = false
	_refresh_busy()

func _check_end() -> void:
	if model.is_won():
		if completion_handled: return
		completion_handled = true
		level_reward = _claim_level_reward(model.level_index)
		overlay = "win"
		unlocked = maxi(unlocked,mini(model.level_index+1,model.level_count()-1))
		_save()
		_play("win")
		if not reduced_motion:
			for i in 40: confetti.append({"position":Vector2(randf_range(10,530),randf_range(-500,0)),"velocity":Vector2(randf_range(-12,12),randf_range(95,170)),"rotation":randf()*TAU,"spin":randf_range(-3,3),"color":Art.COLORS[i%6]})
	elif model.is_stuck(): overlay = "stuck"

func _claim_level_reward(index:int) -> int:
	if index in rewarded_levels: return 0
	rewarded_levels.append(index)
	coins += COMPLETION_REWARD
	_sync_coins()
	return COMPLETION_REWARD

func _sync_coins() -> void:
	if coin_badge: coin_badge.amount = coins
	if road_menu: road_menu.coin_badge.amount = coins

func _undo() -> void:
	if busy or history.is_empty(): return
	var previous = history.pop_back()
	if model.restore(previous.state):
		moves = previous.moves
		boarded = previous.boarded
		cargo_trips = previous.get("cargo_trips",0)
		load_feedback.clear()
		overlay = ""
		hint_bus = -1
		reject_time = 0
		_sync_visuals()
		_message("Машины и конвейер вернулись на ход назад")

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
	toast = value
	toast_time = 3.0

func _input(event:InputEvent) -> void:
	if overlay == "road_menu":
		if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE: _back()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE: _back()
	if not (event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT): return
	var p = get_global_mouse_position()
	if overlay != "":
		_overlay_input(p)
		return
	if Rect2(143,1103,54,54).has_point(p): _undo()
	elif Rect2(243,1103,54,54).has_point(p): _hint()
	elif Rect2(343,1103,54,54).has_point(p): _show_road_menu(true)
	else:
		var candidate = -1
		var nearest = INF
		for bus in model.buses:
			if bus.status != "yard": continue
			var local = (p-bus.position).rotated(-bus.angle)
			var size: Vector2 = model.vehicle_size(bus)
			if Rect2(-size/2,size).grow(6).has_point(local):
				var distance = p.distance_squared_to(bus.position)
				if distance < nearest:
					candidate = bus.id
					nearest = distance
		if candidate >= 0: _dispatch(candidate)

func _overlay_input(p:Vector2) -> void:
	if overlay == "settings":
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
		if Rect2(76,570,388,62).has_point(p):
			if model.level_index+1 < model.level_count(): _load_level(model.level_index+1)
			else:
				levels_origin = "win"
				_show_road_menu(false)
		elif Rect2(76,654,388,50).has_point(p): _load_level(model.level_index)
	elif overlay == "stuck":
		if Rect2(76,558,388,62).has_point(p): _undo()
		elif Rect2(76,642,388,50).has_point(p): _load_level(model.level_index)

func _show_road_menu(resumable:bool=true) -> void:
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

func _draw() -> void:
	if overlay == "road_menu": return
	if art == null: return
	draw_rect(Rect2(0,0,540,1171),PAPER)
	draw_texture_rect(FACTORY,Rect2(0,0,540,809.0*540.0/1179.0),false)
	_draw_conveyor()
	_draw_loading()
	_draw_yard()
	for bus in model.buses:
		if bus.status in ["yard","docked"]: _draw_truck(bus)
	for bus in model.buses:
		if bus.status in ["arriving","leaving"]: _draw_truck(bus)
	_draw_impact()
	var visible_carry = worker_carry if worker_batch_count>0 else -1
	art.worker(worker_position+Vector2(-worker_lift*7,-worker_lift*5),visible_carry,worker_walking and not reduced_motion,elapsed*19,worker_batch_count)
	if collecting:
		var a = _belt_cargo_center(worker_batch_count)
		var b = worker_position+Vector2(14,-9)
		var p = a.bezier_interpolate(a+Vector2(0,12),b+Vector2(14,-22),b,batch_pickup)
		art.material(p,worker_carry,lerpf(_belt_cargo_scale(worker_carry),0.58,batch_pickup))
	for feedback in load_feedback:
		var pos: Vector2 = feedback.position+Vector2(0,-feedback.age*22)
		_round(Rect2(pos-Vector2(20,13),Vector2(40,24)),Color("127f49"),9)
		_text("+%d" % feedback.count,pos+Vector2(0,5),15,Color.WHITE,true)
	_draw_header()
	_draw_footer()
	if toast_time>0 and overlay=="":
		_round(Rect2(25,1064,490,31),INK,10)
		_text(toast,Vector2(270,1085),12,Color.WHITE,true)
	if overlay!="": _draw_overlay()

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
	var selected = hint_bus==bus.id
	art.vehicle(bus,visual.position,visual.angle,1.0,selected,rejected)

func _draw_footer() -> void:
	draw_rect(Rect2(0,1099,540,72),PAPER)
	for i in GAME_ICONS.size():
		var center := Vector2(170+i*100,1130)
		var enabled: bool = i==2 or (not busy and (i!=0 or not history.is_empty()))
		var region: Rect2 = game_icon_regions[i]
		var fit: float = minf(54.0/region.size.x,54.0/region.size.y)
		var drawn: Vector2 = region.size*fit
		var tint := Color(1,1,1,1.0 if enabled else 0.4)
		draw_texture_rect_region(GAME_ICONS[i],Rect2(center-drawn*0.5,drawn),region,tint)

func _draw_overlay() -> void:
	draw_rect(Rect2(0,0,540,1171),Color(0.12,0.20,0.24,0.47))
	_round(Rect2(52,224,436,515),Color("ffffff"),30)
	if overlay=="settings":
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
	elif overlay=="win":
		for particle in confetti:
			if particle.position.y<960:
				draw_set_transform(particle.position,particle.rotation)
				_round(Rect2(-3,-6,6,12),particle.color,2)
				draw_set_transform(Vector2.ZERO)
		draw_circle(Vector2(270,331),57,Color("f6e5b7"))
		var coin_region: Rect2 = coin_badge.region
		var coin_size: Vector2 = coin_region.size*minf(84.0/coin_region.size.x,84.0/coin_region.size.y)
		draw_texture_rect_region(CoinBadge.ICON,Rect2(Vector2(270,331)-coin_size/2,coin_size),coin_region)
		_text("Заказ отправлен!",Vector2(270,431),31,INK,true)
		_text("+%d монет" % level_reward if level_reward>0 else "Награда за этот уровень уже получена",Vector2(270,463),18,INK,true)
		_text("%d грузов  ·  %d машин  ·  %d ходов" % [total_passengers,model.buses.size(),moves],Vector2(270,509),14,INK,true)
		_button(Rect2(76,570,388,62),"Следующий склад" if model.level_index<model.level_count()-1 else "Все склады разгружены!",true)
		_text("Сыграть ещё раз",Vector2(270,686),16,INK,true)
	elif overlay=="stuck":
		draw_circle(Vector2(270,330),55,Color("f6dfc9"))
		_text("!",Vector2(270,351),52,Color("cb9261"),true)
		_text("Погрузка остановилась",Vector2(270,431),27,INK,true)
		_text("Для следующего груза нет свободного пути.",Vector2(270,473),14,MUTED,true)
		_text("Отмени ход и выбери другую машину.",Vector2(270,501),15,MUTED,true)
		_button(Rect2(76,558,388,62),"Вернуться на ход назад",true)
		_text("Начать заново",Vector2(270,675),16,INK,true)

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
	coins = maxi(0,int(cfg.get_value("economy","coins",0)))
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
