extends Control
@export var sky_texture: Texture2D = preload("res://assets/artwork/menu/Cheerful Cartoon Cloudscape.png")
var horizon_fraction = 0.26
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("bdeaf6"))
	if not sky_texture: return
	var sky_size = Vector2(size.x,size.y*horizon_fraction)
	var source_size = sky_texture.get_size()
	var fit_scale = maxf(sky_size.x/source_size.x,sky_size.y/source_size.y)
	var crop_size = sky_size/fit_scale
	draw_texture_rect_region(sky_texture,Rect2(Vector2.ZERO,sky_size),Rect2(Vector2((source_size.x-crop_size.x)*0.5,0),crop_size))
