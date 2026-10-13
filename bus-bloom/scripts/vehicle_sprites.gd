extends RefCounted
## User artwork stays unchanged on disk. Small, recolored textures are cached once
## at startup; only paint hues change, retaining windows, tyres and bed detail.

const PICKUP = preload("res://assets/artwork/vehicles/Blue-pickup.png")
const PICKUP_RECOLOR_BASE = preload("res://assets/artwork/vehicles/Pickup-recolor-base.png")
const GREEN_DUMP = preload("res://assets/artwork/vehicles/Green Dump Truck.png")
const ORANGE_DUMP = preload("res://assets/artwork/vehicles/Orange Dump Truck.png")
const FLATBED = preload("res://assets/artwork/vehicles/Red Flatbed Truck.png")
const PALETTE = [Color("ffb000"),Color("ff8614"),Color("ff52b5"),Color("27ce16"),Color("078fff"),Color("ff3535")]
const FOOTPRINTS = [Vector2(56.0,98.24),Vector2(56.0,139.37),Vector2(56.0,182.79)]
const CAPACITIES = [2,4,6]
static var _textures: Dictionary = {}
static var _bases: Dictionary = {}

static func _source(kind:int, material_id:int) -> Texture2D:
	if kind==0: return PICKUP if material_id==4 else PICKUP_RECOLOR_BASE
	if kind==2: return FLATBED
	return ORANGE_DUMP if material_id in [0,1] else GREEN_DUMP

static func source_path(kind:int, material_id:int) -> String:
	return _source(kind,material_id).resource_path

static func prepare() -> void:
	for kind in 3:
		for material_id in 6:
			get_texture(kind,material_id)

static func get_texture(kind:int, material_id:int) -> Texture2D:
	var key: int = kind*6+material_id
	if _textures.has(key): return _textures[key]
	var source: Texture2D = _source(kind,material_id)
	var path: String = source.resource_path
	if not _bases.has(path):
		var original: Image = source.get_image()
		if original.is_compressed(): original.decompress()
		original.convert(Image.FORMAT_RGBA8)
		original.resize(roundi(original.get_width()*256.0/original.get_height()),256,Image.INTERPOLATE_LANCZOS)
		_bases[path] = original
	var painted: Image = _bases[path].duplicate()
	# Keep the user's revised blue exactly; other colors use the earlier neutral-detail base.
	if kind==0 and material_id==4:
		painted.generate_mipmaps()
		var original_texture: ImageTexture = ImageTexture.create_from_image(painted)
		_textures[key] = original_texture
		return original_texture
	var base_hue: float = 0.571 if kind==0 else (0.995 if kind==2 else (0.082 if material_id in [0,1] else 0.292))
	var target: Color = PALETTE[material_id]
	for y in painted.get_height():
		for x in painted.get_width():
			var pixel: Color = painted.get_pixel(x,y)
			if pixel.a<0.01 or pixel.s<0.38: continue
			var hue_distance: float = absf(pixel.h-base_hue)
			hue_distance = minf(hue_distance,1.0-hue_distance)
			var weight: float = smoothstep(0.38,0.66,pixel.s)*(1.0-smoothstep(0.035,0.09,hue_distance))
			if weight<0.001: continue
			var saturation: float = clampf(pixel.s*target.s/0.9,0.0,1.0)
			var value: float = pixel.v*lerpf(0.78,1.0,target.v)
			if material_id==2:
				# Pink cement carriers retain body shading and neutral glass/bed details.
				saturation = maxf(saturation,target.s)
				value = lerpf(pixel.v,1.0,0.3)
			elif material_id==5:
				# Keep roofing-sheet carriers bright red even on the darker green base.
				value = lerpf(pixel.v,1.0,0.42)
				saturation = maxf(saturation,target.s)
			var replacement: Color = Color.from_hsv(target.h,saturation,value,pixel.a)
			painted.set_pixel(x,y,pixel.lerp(replacement,weight))
	painted.generate_mipmaps()
	var texture: ImageTexture = ImageTexture.create_from_image(painted)
	_textures[key] = texture
	return texture

static func draw_rect(kind:int, _material_id:int) -> Rect2:
	# Deliberately normalize all complete silhouettes to the same width. Lengths
	# reproduce the three measured classes in the user's 1179 px layout.
	var size: Vector2 = FOOTPRINTS[clampi(kind,0,2)]
	return Rect2(-size*0.5,size)

static func bed_rect(kind:int, material_id:int) -> Rect2:
	# Safe floor areas measured against each supplied image, excluding cabin,
	# front bulkhead, side walls and tailgate. Normalized coordinates follow the body.
	var floor_uv: Rect2
	if kind==0: floor_uv = Rect2(0.21,0.505,0.58,0.365)
	elif kind==2: floor_uv = Rect2(0.18,0.26,0.635,0.625)
	elif material_id in [0,1]: floor_uv = Rect2(0.25,0.44,0.50,0.39)
	else: floor_uv = Rect2(0.258,0.435,0.493,0.395)
	var body: Rect2 = draw_rect(kind,material_id)
	return Rect2(body.position+floor_uv.position*body.size,floor_uv.size*body.size)

static func cargo_scale(kind:int, material_id:int) -> float:
	var bed: Rect2 = bed_rect(kind,material_id)
	# A single file fits these long beds and keeps every unit separately visible.
	# Every cropped cargo fits a 26 x 28.4 box; leave space between each unit.
	return minf(1.0,minf((bed.size.x-2.0)/26.0,(bed.size.y-2.0)/(CAPACITIES[kind]*29.0)))

static func cargo_slots(kind:int, material_id:int) -> Array[Vector2]:
	var bed: Rect2 = bed_rect(kind,material_id)
	var slots: Array[Vector2] = []
	for index in CAPACITIES[kind]:
		slots.append(Vector2(bed.get_center().x,bed.position.y+bed.size.y*(index+0.5)/CAPACITIES[kind]))
	return slots
