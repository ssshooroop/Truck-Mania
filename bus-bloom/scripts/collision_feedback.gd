extends RefCounted
## Contact uses the opaque artwork, excluding transparent margins and cast shadow.
const Sprites = preload("res://scripts/vehicle_sprites.gd")
static var masks: Dictionary = {}

static func silhouette(bus:Dictionary) -> Dictionary:
	var key:int = bus.kind*6+bus.color
	if masks.has(key): return masks[key]
	var image:Image = Sprites.get_texture(bus.kind,bus.color).get_image()
	var size:Vector2 = Sprites.draw_rect(bus.kind,bus.color).size
	image.resize(ceili(size.x*2),ceili(size.y*2),Image.INTERPOLATE_NEAREST)
	var points := PackedVector2Array()
	var front := PackedFloat32Array()
	front.resize(image.get_width())
	front.fill(INF)
	for x in image.get_width():
		for y in image.get_height():
			if image.get_pixel(x,y).a < 0.5: continue
			var p := Vector2((x+0.5)/image.get_width(),(y+0.5)/image.get_height())*size-size*0.5
			front[x] = minf(front[x],p.y)
			# Only silhouette boundary pixels are needed for a first contact.
			if x==0 or y==0 or x==image.get_width()-1 or y==image.get_height()-1 or image.get_pixel(x-1,y).a<0.5 or image.get_pixel(x+1,y).a<0.5 or image.get_pixel(x,y-1).a<0.5 or image.get_pixel(x,y+1).a<0.5:
				points.append(p)
	var result := {"points":points,"front":front,"size":size}
	masks[key] = result
	return result

static func contact(model, id:int) -> Dictionary:
	var moving:Dictionary = model.get_bus(id)
	var mask := silhouette(moving)
	var best := INF
	var result:Dictionary = {}
	for other:Dictionary in model.buses:
		if other.id == id or other.status != "yard": continue
		for local:Vector2 in silhouette(other).points:
			var world:Vector2 = other.position+(local*model.layout_scale).rotated(other.angle)
			var relative:Vector2 = (world-moving.position).rotated(-moving.angle)/model.layout_scale
			var column:int = floori((relative.x/mask.size.x+0.5)*mask.front.size())
			if column<0 or column>=mask.front.size() or not is_finite(mask.front[column]): continue
			var distance:float = (mask.front[column]-relative.y)*model.layout_scale
			if distance < -0.6*model.layout_scale or distance >= best: continue
			best = maxf(0,distance)
			result = {"distance":best,"point":world,"obstacle":other.id,"direction":model.forward(moving)}
	if result.is_empty():
		result = body_contact(model,id)
	return result

static func body_contact(model,id:int) -> Dictionary:
	var moving:Dictionary = model.get_bus(id)
	var direction:Vector2 = model.forward(moving)
	var side := Vector2(-direction.y,direction.x)
	var size:Vector2 = model.vehicle_size(moving)
	var best := INF
	var result:Dictionary = {}
	for other_id in model.blocking_ids(id):
		var other:Dictionary = model.get_bus(other_id)
		var forward:Vector2 = model.forward(other)
		var across := Vector2(-forward.y,forward.x)
		var other_size:Vector2 = model.vehicle_size(other)
		var delta:Vector2 = other.position-moving.position
		var enter := 0.0
		var leave := INF
		for axis:Vector2 in [direction,side,forward,across]:
			var radius:float = absf(axis.dot(side))*size.x*0.5+absf(axis.dot(direction))*size.y*0.5+absf(axis.dot(across))*other_size.x*0.5+absf(axis.dot(forward))*other_size.y*0.5
			var speed:float = direction.dot(axis)
			var offset:float = delta.dot(axis)
			if absf(speed)<0.00001:
				if absf(offset)>radius: leave = -1.0
			else:
				var a:float = (offset-radius)/speed
				var b:float = (offset+radius)/speed
				enter = maxf(enter,minf(a,b))
				leave = minf(leave,maxf(a,b))
		if enter>leave or enter>=best: continue
		best = enter
		var center:Vector2 = moving.position+direction*enter
		var nearest := Vector2.ZERO
		var nearest_distance := INF
		for local:Vector2 in silhouette(other).points:
			var point:Vector2 = other.position+(local*model.layout_scale).rotated(other.angle)
			var relative:Vector2 = (point-center).rotated(-moving.angle)
			var closest := relative.clamp(-size*0.5,size*0.5)
			var distance:float = relative.distance_squared_to(closest)
			if distance<nearest_distance:
				nearest_distance = distance
				nearest = point
		result = {"distance":best,"point":nearest,"obstacle":other_id,"direction":direction}
	return result
