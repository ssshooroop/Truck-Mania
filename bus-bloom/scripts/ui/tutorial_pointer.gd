extends RefCounted
## The fingertip is the anchor; the hand travels along the pointing direction.
const TEXTURE=preload("res://assets/artwork/menu/pointer.png")
static func draw(c:CanvasItem,tip:Vector2,direction:Vector2,age:float,reduced:bool,base:Transform2D=Transform2D.IDENTITY) -> void:
	var travel := 0.0 if reduced else (1.0-cos(age*TAU/1.4))*6.0
	var angle := Vector2(-0.26,-0.966).angle_to(direction.normalized())
	var zoom := 92.0/297.0
	var anchor := Vector2(105,20)*zoom
	c.draw_set_transform_matrix(base*Transform2D(angle,tip+direction.normalized()*travel))
	c.draw_texture_rect(TEXTURE,Rect2(-anchor,Vector2(TEXTURE.get_size())*zoom),false)
	c.draw_set_transform_matrix(base)
