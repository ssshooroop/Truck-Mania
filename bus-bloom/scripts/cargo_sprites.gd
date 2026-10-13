extends RefCounted
## Original transparent artwork is never changed. A cropped, mipmapped runtime
## copy keeps each physical cargo silhouette clear on the belt and in the bed.

const SOURCES = [
	preload("res://assets/artwork/cargo/Wood-yellow.png"),
	preload("res://assets/artwork/cargo/Brick-bright-orange.png"),
	preload("res://assets/artwork/cargo/Cement-gray.png"),
	preload("res://assets/artwork/cargo/Cable-green.png"),
	preload("res://assets/artwork/cargo/Blue-pipe.png"),
	preload("res://assets/artwork/cargo/Sheet-bright-red.png")
]
const FOOTPRINT = Vector2(26.0,28.4)
static var _textures: Dictionary = {}
static var _rects: Dictionary = {}

static func prepare() -> void:
	for index in SOURCES.size():
		get_texture(index)

static func get_texture(index: int) -> Texture2D:
	index = clampi(index,0,SOURCES.size()-1)
	if _textures.has(index): return _textures[index]
	var original: Image = SOURCES[index].get_image()
	if original.is_compressed(): original.decompress()
	original.convert(Image.FORMAT_RGBA8)
	var used: Rect2i = original.get_used_rect()
	var cropped: Image = original.get_region(used)
	var native_size := Vector2(cropped.get_width(),cropped.get_height())
	var fit: float = minf(FOOTPRINT.x/native_size.x,FOOTPRINT.y/native_size.y)
	_rects[index] = Rect2(-native_size*fit*0.5,native_size*fit)
	var reduction: float = 192.0/maxf(native_size.x,native_size.y)
	cropped.resize(maxi(1,roundi(native_size.x*reduction)),maxi(1,roundi(native_size.y*reduction)),Image.INTERPOLATE_LANCZOS)
	if index==2:
		# Tint packaging at runtime, preserving dark ink, folds and alpha.
		var pink := Color("ff52b5")
		for y in cropped.get_height():
			for x in cropped.get_width():
				var pixel := cropped.get_pixel(x,y)
				if pixel.a<0.01: continue
				var weight: float = smoothstep(0.24,0.55,pixel.v)
				var tinted := Color.from_hsv(pink.h,pink.s,lerpf(pixel.v,1.0,0.3),pixel.a)
				cropped.set_pixel(x,y,pixel.lerp(tinted,weight))
	cropped.generate_mipmaps()
	var texture := ImageTexture.create_from_image(cropped)
	_textures[index] = texture
	return texture

static func draw_rect(index: int) -> Rect2:
	index = clampi(index,0,SOURCES.size()-1)
	get_texture(index)
	return _rects[index]
