extends Node2D

var level_index = 0
var unlocked = 0
var reduced_motion = false
var age = 0.0

func _process(delta:float) -> void:
	age += delta
	queue_redraw()

func _draw() -> void:
	var current = level_index==unlocked
	var locked = level_index>unlocked
	var radius = 34.0
	if current:
		var pulse = 0.0 if reduced_motion else sin(age*2.5)*2.0
		draw_circle(Vector2.ZERO,43+pulse,Color(1,0.88,0.25,0.3))
	draw_circle(Vector2(0,6),radius,Color("23374c"))
	draw_circle(Vector2.ZERO,radius,Color("9daab8") if locked else Color("ffc626") if current else Color("2ebc85"))
	draw_arc(Vector2.ZERO,radius-3,0,TAU,48,Color(1,1,1,0.65),2,true)
	var label = str(level_index+1)
	var font = ThemeDB.fallback_font
	var width = font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,27).x
	draw_string(font,Vector2(-width/2,9),label,HORIZONTAL_ALIGNMENT_LEFT,-1,27,Color("243449"))
	if locked:
		draw_arc(Vector2(23,-28),5,PI,TAU,12,Color.WHITE,2,true)
		draw_rect(Rect2(16,-28,14,10),Color.WHITE)
	elif not current:
		draw_polyline(PackedVector2Array([Vector2(17,-29),Vector2(23,-23),Vector2(34,-36)]),Color.WHITE,3,true)

func hit(point:Vector2) -> bool:
	return visible and global_position.distance_to(point)<42.0*scale.x
