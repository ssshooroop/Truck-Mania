extends RefCounted
## User vehicle and material sprites with a procedural worker. Public methods restore the canvas transform.
## Vehicles face local -Y. All dimensions match the model's clearance rectangles.

const Vehicles = preload("res://scripts/vehicle_sprites.gd")
const Cargo = preload("res://scripts/cargo_sprites.gd")

const COLORS = [
	Color("ffb000"), Color("ff8614"), Color("ff52b5"),
	Color("27ce16"), Color("078fff"), Color("ff3535")
]
const NAMES = ["Доски", "Кирпичи", "Цемент", "Кабель", "Трубы", "Профнастил"]
const TYPE_NAMES = ["Пикап", "Самосвал", "Бортовой"]
const INK = Color("172d45")
const TYRE = Color("273846") # Also used for the worker's boots.

var canvas: Node2D
var font: Font
var _styles: Dictionary = {}
var _cargo_pop: Dictionary = {}

func _init(target: Node2D, ui_font: Font) -> void:
	canvas = target
	font = ui_font
	Vehicles.prepare()
	Cargo.prepare()
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

func _box(rect: Rect2, fill: Color, radius: int = 3, border: Color = Color.TRANSPARENT, border_width: int = 0) -> void:
	var key: String = fill.to_html() + str(radius) + border.to_html() + str(border_width)
	if not _styles.has(key):
		var style := StyleBoxFlat.new()
		style.bg_color = fill
		style.corner_radius_top_left = radius
		style.corner_radius_top_right = radius
		style.corner_radius_bottom_left = radius
		style.corner_radius_bottom_right = radius
		style.border_color = border
		style.set_border_width_all(border_width)
		style.anti_aliasing = true
		style.anti_aliasing_size = 0.6
		_styles[key] = style
	canvas.draw_style_box(_styles[key], rect)

func _poly(points: Array, fill: Color) -> void:
	canvas.draw_colored_polygon(PackedVector2Array(points), fill)

func _line(from: Vector2, to: Vector2, color: Color, width: float = 1.0) -> void:
	canvas.draw_line(from, to, color, width, true)

func vehicle(bus: Dictionary, position: Vector2, angle: float, scale: float = 1.0, selected: bool = false, _blocked: bool = false) -> void:
	var kind: int = clampi(int(bus.get("kind", 0)), 0, 2)
	var material_id: int = clampi(int(bus.get("color", 0)), 0, 5)
	var tint: Color = COLORS[material_id]
	var body: Rect2 = Vehicles.draw_rect(kind,material_id)
	var half: Vector2 = body.size*0.5
	var size: Vector2 = body.size
	var capacity: int = int(bus.get("capacity", 4))
	var load_count: int = int(bus.get("load", 0))
	canvas.draw_set_transform(position, angle, Vector2.ONE * scale)
	if selected:
		_box(body.grow(4), Color(1,0.9,0.15,0.3), 7, Color("ffcb00"), 2)
	# Preserve the complete supplied silhouette, including mirrors and wheels.
	canvas.draw_texture_rect(Vehicles.get_texture(kind,material_id),Rect2(body.position+Vector2(1.8,2.2),body.size),false,Color(0.12,0.20,0.3,0.22))
	canvas.draw_texture_rect(Vehicles.get_texture(kind,material_id),body,false)
	# Yard arrows describe clearance; a docked bed displays each real cargo unit.
	var state: String = str(bus.get("status", "yard"))
	if state in ["docked", "leaving"]:
		_draw_loaded_cargo(bus, position, angle, scale, kind, material_id, load_count)
	else:
		var arrow_y: float = Vehicles.bed_rect(kind,material_id).get_center().y - 2.0
		if kind == 0:
			arrow_y -= maxf(0.0, absf(sin(angle)) * 12.0 + absf(cos(angle)) * 5.5 - 6.0) * 1.3
		_arrow(Vector2(0.8, arrow_y + 1.1), Color(0.15, 0.25, 0.34, 0.22))
		_arrow(Vector2(0, arrow_y), Color("fffef1"))
	# Keep the capacity upright even when a truck points south or diagonally.
	# Project the screen-aligned pill into the vehicle axis to retain its rear inset.
	var label_depth: float = absf(sin(angle)) * 12.0 + absf(cos(angle)) * 5.5
	var label_y: float = half.y - maxf(6.0, label_depth + 0.6)
	if scale >= 0.95 and state not in ["docked","leaving"]:
		var label_anchor: Vector2 = position + Vector2(0, label_y).rotated(angle) * scale
		canvas.draw_set_transform(label_anchor, 0, Vector2.ONE * scale)
		_box(Rect2(-12, -5.5, 24, 11), Color("fff9e9"), 3, tint.darkened(0.2), 1)
		_material_at(Vector2(-6.4, 0), material_id, 0.31)
		if font != null:
			canvas.draw_string(font, Vector2(-0.5, 3.6), str(capacity), HORIZONTAL_ALIGNMENT_CENTER, 10, 10, INK)
		canvas.draw_set_transform(position, angle, Vector2.ONE * scale)
	if load_count > 0:
		var ratio: float = clampf(float(load_count) / maxi(capacity, 1), 0.0, 1.0)
		_box(Rect2(-half.x + 3, half.y + 1.5, size.x - 6, 2.8), INK, 1)
		_box(Rect2(-half.x + 3, half.y + 1.5, (size.x - 6) * ratio, 2.8), Color("a7ed8c"), 1)
	canvas.draw_set_transform(Vector2.ZERO)


func _draw_loaded_cargo(bus: Dictionary, position: Vector2, angle: float, scale: float, kind: int, material_id: int, load_count: int) -> void:
	var slots: Array[Vector2] = Vehicles.cargo_slots(kind,material_id)
	var id: int = int(bus.get("id", -1))
	var now: float = float(canvas.get("elapsed"))
	var animate: bool = not bool(canvas.get("reduced_motion"))
	var visible_count: int = mini(load_count, slots.size())
	if not _cargo_pop.has(id) or int(_cargo_pop[id].count) != visible_count:
		var previous_count: int = int(_cargo_pop[id].count) if _cargo_pop.has(id) else 0
		_cargo_pop[id] = {"count": visible_count, "from": previous_count, "time": now}
	for index in range(visible_count):
		var icon_scale: float = Vehicles.cargo_scale(kind,material_id)
		if animate and index >= int(_cargo_pop[id].from):
			var progress: float = clampf((now - float(_cargo_pop[id].time)) / 0.22, 0.0, 1.0)
			icon_scale *= lerpf(0.38, 1.0, 1.0 - pow(1.0 - progress, 3.0))
		canvas.draw_set_transform(position + slots[index].rotated(angle) * scale, angle, Vector2.ONE * scale * icon_scale)
		_draw_material(material_id)
	canvas.draw_set_transform(position, angle, Vector2.ONE * scale)

func _arrow(offset: Vector2, fill: Color) -> void:
	_poly([offset + Vector2(0, -9), offset + Vector2(6.5, -2.5), offset + Vector2(2.4, -2.5),
		offset + Vector2(2.4, 6), offset + Vector2(-2.4, 6), offset + Vector2(-2.4, -2.5),
		offset + Vector2(-6.5, -2.5)], fill)

func material(position: Vector2, index: int, scale: float = 1.0) -> void:
	canvas.draw_set_transform(position, 0, Vector2.ONE * scale)
	_draw_material(clampi(index, 0, 5))
	canvas.draw_set_transform(Vector2.ZERO)

func _material_at(position: Vector2, index: int, scale: float) -> void:
	# Draw in the caller's current transform, including upright capacity badges.
	var icon: Rect2 = Cargo.draw_rect(index)
	canvas.draw_texture_rect(Cargo.get_texture(index),Rect2(position+icon.position*scale,icon.size*scale),false)

func _draw_material(index: int) -> void:
	canvas.draw_texture_rect(Cargo.get_texture(index),Cargo.draw_rect(index),false)

func worker(position: Vector2, carrying: int = -1, walking: bool = false, phase: float = 0.0, count: int = 1) -> void:
	var step: float = sin(phase) * 2.4 if walking else 0.0
	canvas.draw_set_transform(position, 0, Vector2.ONE * 1.15)
	canvas.draw_circle(Vector2(1,9),8,Color(0.12,0.23,0.28,0.15))
	_box(Rect2(-5,4+step,4,7),Color("16416b"),2)
	_box(Rect2(1,4-step,4,7),Color("16416b"),2)
	_box(Rect2(-6,9+step,5,3),TYRE,1)
	_box(Rect2(1,9-step,5,3),TYRE,1)
	_box(Rect2(-7,-7,14,14),Color("d5f000"),4,Color("526514"),1)
	_line(Vector2(-3,-5),Vector2(-3,5),Color("ffffff"),1.8)
	_line(Vector2(3,-5),Vector2(3,5),Color("ffffff"),1.8)
	_line(Vector2(-6,1),Vector2(6,1),Color("ffffff"),1.5)
	_line(Vector2(-7,-4),Vector2(-9,2+step),Color("efaf7b"),4)
	_line(Vector2(7,-4),Vector2(11,0) if carrying>=0 else Vector2(9,2-step),Color("efaf7b"),4)
	canvas.draw_circle(Vector2(0,-10),5.2,Color("f4c69b"))
	canvas.draw_circle(Vector2(-1.8,-9),0.7,INK)
	canvas.draw_circle(Vector2(1.8,-9),0.7,INK)
	_line(Vector2(-1,-6.8),Vector2(1,-6.8),Color("b97963"),0.7)
	canvas.draw_circle(Vector2(0,-13),6,Color("b83f00"))
	canvas.draw_circle(Vector2(-0.5,-14),5.3,Color("ff6400"))
	_box(Rect2(-7,-12,14,3),Color("ff8100"),2,Color("b83f00"),1)
	_line(Vector2(-1,-18),Vector2(-1,-14),Color("fff3a8"),1.4)
	if carrying >= 0:
		# A compact stack communicates the batch without obscuring the orange helmet.
		var visible_layers: int = mini(maxi(count,1),3)
		for layer in range(visible_layers):
			var cargo_offset := Vector2(13 + layer * 0.4, -1 - layer * 3.8)
			canvas.draw_set_transform(position + cargo_offset * 1.15, -0.10, Vector2.ONE * 0.50 * 1.15)
			_draw_material(clampi(carrying,0,5))
		if count > 1:
			canvas.draw_set_transform(position, 0, Vector2.ONE * 1.15)
			_box(Rect2(12,3,18,11),INK,4,Color.WHITE,1)
			if font != null:
				canvas.draw_string(font,Vector2(13,11),"×%d" % count,HORIZONTAL_ALIGNMENT_CENTER,16,9,Color.WHITE)
	canvas.draw_set_transform(Vector2.ZERO)
