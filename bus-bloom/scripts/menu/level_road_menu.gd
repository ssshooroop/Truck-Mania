extends Control

signal level_selected(index:int)
signal settings_requested
signal shop_requested
signal resume_requested
signal preference_changed(key:String,enabled:bool)
const PreferenceIcon = preload("res://scripts/menu/preference_icon.gd")
const Scroller = preload("res://scripts/menu/road_scroller.gd")
const Marker = preload("res://scripts/menu/level_marker.gd")
const Decoration = preload("res://scripts/menu/road_decoration.gd")
const Background = preload("res://scripts/menu/landmark_background.gd")
@export var projection: Resource = preload("res://scenes/menu/road_projection.tres")
@export_range(0.1,0.4) var road_top: float = 0.26
@export_range(0.6,1.0) var road_bottom: float = 1.0
@export var level_spacing: float = 0.19
@export var inertia_friction: float = 5.0
@export var drag_speed: float = 1.0
var road
var background
var markers: Array = []
var decorations: Array = []
var decoration_first = 2147483647
var unlocked = 0
var reduced_motion = false
var can_resume = false
var input_blocked := false
var touch_id = -1
var pressed = false
var start_point = Vector2.ZERO
var last_point = Vector2.ZERO
var last_time = 0
var distance_dragged = 0.0
var preference_icons: Dictionary = {}
var resume_level = -1
var settings_button: TextureButton
var shop_button: TextureButton
var coin_badge

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visibility_changed.connect(func(): process_mode = Node.PROCESS_MODE_INHERIT if visible else Node.PROCESS_MODE_DISABLED)
	background = Background.new()
	add_child(background)
	road = Scroller.new()
	road.projection = projection
	road.level_spacing = level_spacing
	road.friction = inertia_friction
	road.scroll_speed = drag_speed
	road.snap_enabled = true
	add_child(road)
	var scenery = Node2D.new()
	scenery.y_sort_enabled = true
	add_child(scenery)
	for i in Decoration.CELL_COUNT*Decoration.MEMBERS_PER_CELL:
		var prop = Decoration.new()
		scenery.add_child(prop)
		decorations.append(prop)
	var icon_textures = {
		"music":preload("res://assets/artwork/menu/music.png"),
		"sound":preload("res://assets/artwork/menu/sound.png"),
		"vibration":preload("res://assets/artwork/menu/vibration.png")
	}
	for key in ["music","sound","vibration"]:
		var button = PreferenceIcon.new()
		button.icon = icon_textures[key]
		button.button_pressed = true
		button.toggled.connect(func(enabled:bool): preference_changed.emit(key,enabled))
		add_child(button)
		preference_icons[key] = button
	settings_button = TextureButton.new()
	settings_button.texture_normal = preload("res://assets/artwork/menu/gear.png")
	settings_button.ignore_texture_size = true
	settings_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	settings_button.pressed.connect(func(): settings_requested.emit())
	add_child(settings_button)
	shop_button = TextureButton.new()
	shop_button.texture_normal = preload("res://assets/artwork/menu/shop.png")
	shop_button.ignore_texture_size = true
	shop_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	shop_button.pressed.connect(func(): shop_requested.emit())
	add_child(shop_button)
	coin_badge = preload("res://scripts/coin_badge.gd").new()
	add_child(coin_badge)
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	if not road: return
	background.size = size
	background.horizon_fraction = road_top
	background.queue_redraw()
	road.position = Vector2(0,size.y*road_top)
	road.size = Vector2(size.x,size.y*(road_bottom-road_top))
	var index = 0
	for key in ["music","sound","vibration"]:
		var button = preference_icons[key]
		button.position = Vector2(14,14+index*70)
		button.size = Vector2(60,60)
		index += 1
	settings_button.position = Vector2(size.x-66,16)
	settings_button.size = Vector2(48,48)
	shop_button.position = Vector2(size.x-74,76)
	shop_button.size = Vector2(64,64)
	coin_badge.position = Vector2(size.x/2-67,18)
	coin_badge.size = Vector2(134,44)

func configure(count:int,progress:int,motion_reduced:bool,resumable:bool) -> void:
	unlocked = clampi(progress,0,count-1)
	reduced_motion = motion_reduced
	can_resume = resumable
	for marker in markers: marker.free()
	markers.clear()
	for i in count:
		var marker = Marker.new()
		marker.level_index = i
		marker.unlocked = unlocked
		marker.reduced_motion = reduced_motion
		add_child(marker)
		markers.append(marker)
	road.level_count = count
	road.scroll = road.origin-unlocked*level_spacing
	road.velocity = 0.0
	road.dragging = false
	pressed = false
	touch_id = -1
	_process(0.0)

func sync_preferences(music_on:bool,sound_on:bool,vibration_on:bool) -> void:
	var values = {"music":music_on,"sound":sound_on,"vibration":vibration_on}
	for key in values:
		preference_icons[key].set_pressed_no_signal(values[key])
		preference_icons[key].queue_redraw()

func _process(_delta:float) -> void:
	if not road: return
	var area = Rect2(road.position,road.size)
	for marker in markers:
		_place(marker,road.origin-marker.level_index*level_spacing,0.0,area)
	# Stable seeded layout: returning to a world cell restores its exact grove.
	var first:int = floori(road.scroll/Decoration.CELL_STEP)-int(Decoration.CELL_COUNT/2)
	if first!=decoration_first:
		decoration_first = first
		for cell_index in Decoration.CELL_COUNT:
			var members:Array = Decoration.cell_members(first+cell_index)
			for member_index in Decoration.MEMBERS_PER_CELL:
				var prop = decorations[cell_index*Decoration.MEMBERS_PER_CELL+member_index]
				prop.enabled = member_index<members.size()
				if not prop.enabled: continue
				var data:Dictionary = members[member_index]
				prop.kind = data.kind
				prop.world = data.world
				var center:float = projection.center_x(prop.world)
				var bounds:Vector2 = projection.scenery_edges(prop.world)
				var side:float = data.side
				var width:float = prop.drawn_size().x/540.0
				var available:float = bounds.x if side<0 else 1.0-bounds.y
				var opposite:float = 1.0-bounds.y if side<0 else bounds.x
				if available<width*0.78+0.04 and opposite>available:
					side = -side
					available = opposite
				prop.size_factor = minf(data.size,maxf(0.1,(available-0.04)/width))
				var half_width:float = width*prop.size_factor*0.5
				var x:float
				if side<0:
					x = lerpf(0.02+half_width,bounds.x-0.02-half_width,data.offset)
				else:
					x = lerpf(bounds.y+0.02+half_width,0.98-half_width,data.offset)
				prop.lateral = x-center
				prop.queue_redraw()
	for prop in decorations:
		if not prop.enabled:
			prop.hide()
			continue
		_place(prop,prop.world,prop.lateral,area)
		var distance_to_horizon:float = -(prop.world-road.scroll)*2.0/projection.span
		prop.scale *= prop.size_factor*lerpf(1.0,0.6,smoothstep(0.3,1.0,distance_to_horizon))

func _place(item:Node2D,world:float,lateral:float,area:Rect2) -> void:
	var p:Vector3 = projection.project(world,lateral,road.scroll,area)
	item.visible = p.z>0
	if not item.visible: return
	item.position = Vector2(p.x,p.y)
	item.scale = Vector2.ONE*p.z*size.x/540.0
	var edge = -(world-road.scroll)*2.0/projection.span
	item.modulate.a = 1.0-smoothstep(0.83,1.0,edge)

func set_input_blocked(value:bool) -> void:
	input_blocked = value
	if value:
		pressed = false
		touch_id = -1
		road.dragging = false
		road.velocity = 0

func _input(event:InputEvent) -> void:
	if not visible or input_blocked: return
	if event is InputEventScreenTouch:
		if event.pressed and touch_id==-1:
			touch_id = event.index
			_begin(event.position)
		elif not event.pressed and event.index==touch_id:
			_end(event.position)
			touch_id = -1
	elif event is InputEventScreenDrag and event.index==touch_id:
		_drag(event.position)
	elif event is InputEventMouseButton and event.device!=InputEvent.DEVICE_ID_EMULATION and touch_id==-1:
		if event.button_index==MOUSE_BUTTON_LEFT:
			if event.pressed: _begin(event.position)
			else: _end(event.position)
	elif event is InputEventMouseMotion and event.device!=InputEvent.DEVICE_ID_EMULATION and touch_id==-1 and pressed:
		_drag(event.position)

func _begin(p:Vector2) -> void:
	if not Rect2(road.position,road.size).has_point(p): return
	pressed = true
	start_point = p
	last_point = p
	distance_dragged = 0
	last_time = Time.get_ticks_msec()
	road.velocity = 0
	road.dragging = true

func _drag(p:Vector2) -> void:
	if not pressed: return
	var now = Time.get_ticks_msec()
	var area = Rect2(road.position,road.size)
	var shift:float = (projection.world_at_y(last_point.y,area)-projection.world_at_y(p.y,area))*drag_speed
	road.scroll += shift
	road.velocity = clampf(shift/maxf(0.008,(now-last_time)/1000.0),-1.2,1.2)
	distance_dragged += p.distance_to(last_point)
	last_point = p
	last_time = now

func _end(p:Vector2) -> void:
	if not pressed: return
	pressed = false
	road.dragging = false
	if Time.get_ticks_msec()-last_time>100 or reduced_motion: road.velocity = 0
	if distance_dragged<10 and p.distance_to(start_point)<10:
		road.velocity = 0
		for marker in markers:
			if marker.hit(p) and marker.level_index<=unlocked:
				if can_resume and marker.level_index==resume_level: resume_requested.emit()
				else: level_selected.emit(marker.level_index)
				break

func _notification(what:int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED,NOTIFICATION_APPLICATION_FOCUS_OUT] and road:
		pressed = false
		touch_id = -1
		road.dragging = false
		road.velocity = 0
