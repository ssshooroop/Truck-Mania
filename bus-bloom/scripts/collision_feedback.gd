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
			var world:Vector2 = other.position+local.rotated(other.angle)
			var relative:Vector2 = (world-moving.position).rotated(-moving.angle)
			var column:int = floori((relative.x/mask.size.x+0.5)*mask.front.size())
			if column<0 or column>=mask.front.size() or not is_finite(mask.front[column]): continue
			var distance:float = mask.front[column]-relative.y
			if distance < -0.6 or distance >= best: continue
			best = maxf(0,distance)
			result = {"distance":best,"point":world,"obstacle":other.id,"direction":model.forward(moving)}
	return result
