extends RefCounted
## Fold the outer service lanes onto the visible screen margins. The same
## mapping is used by rendering and swept-body verification, including turns.
const SCREEN = Vector2(540,1171)
const YARD = Rect2(35,610,470,480)
const INSET = 1.0 # Authored bodies have a two-pixel inset inside the yard.

static func position_for(point:Vector2,angle:float,size:Vector2) -> Vector2:
	var side := Vector2(cos(angle),sin(angle)).abs()
	var forward := Vector2(sin(angle),-cos(angle)).abs()
	var half := (side*size.x+forward*size.y)*0.5
	# On a straight side lane, 1/3 of the width is outside. While turning,
	# preserve clearance from the packed yard, keeping part of the body visible.
	var left := minf(half.x/3.0,YARD.position.x+INSET-half.x)
	var right := maxf(SCREEN.x-half.x/3.0,YARD.end.x-INSET+half.x)
	var bottom := maxf(SCREEN.y-half.y/3.0,YARD.end.y+INSET+half.y)
	return Vector2(clampf(point.x,left,right),minf(point.y,bottom))
