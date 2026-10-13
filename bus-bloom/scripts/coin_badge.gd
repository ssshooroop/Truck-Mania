extends Control
## Shared balance display; deliberately ignores pointer input.
const ICON = preload("res://assets/artwork/menu/coin.png")
var amount: int = 0:
	set(value):
		amount = maxi(0,value)
		queue_redraw()
var region: Rect2

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	region = Rect2(ICON.get_image().get_used_rect())
	resized.connect(queue_redraw)

func _draw() -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("172737")
	panel.set_corner_radius_all(16)
	draw_style_box(panel,Rect2(Vector2.ZERO,size))
	var fit: float = minf(34.0/region.size.x,34.0/region.size.y)
	var drawn := region.size*fit
	draw_texture_rect_region(ICON,Rect2(Vector2(24,size.y/2)-drawn/2,drawn),region)
	var font := ThemeDB.fallback_font
	var value := str(amount)
	var font_size := 22
	while font_size>12 and font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>size.x-54:
		font_size -= 1
	draw_string(font,Vector2(47,(size.y+font.get_ascent(font_size)-font.get_descent(font_size))/2),value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color.WHITE)
