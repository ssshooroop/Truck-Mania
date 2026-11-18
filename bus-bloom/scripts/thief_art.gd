extends RefCounted
const Cargo = preload("res://scripts/cargo_sprites.gd")
static var frames:Dictionary={}
const DURATION=5.6
const CONTACT=2.15
const BELT_SLIDE_START=3.75
const BELT_SLIDE_END=4.15
static func prepare() -> void:
	if not frames.is_empty(): return
	for kind in ["run","carry","jump","jump_empty","sit"]:
		frames[kind]=[]
		for i in (5 if kind in ["jump","sit"] else 4):
			var path:String="res://assets/artwork/thief/thief-jump-cargo/thief-jump-cargo-%d.png"%(i+1) if kind=="jump" else "res://assets/artwork/thief/thief-%s/thief-%s%d.png"%[kind,kind,i+1]
			if kind=="jump_empty": path="res://assets/artwork/thief/thief-jump-empty/thief-jump-empty%d.png"%(i+1)
			frames[kind].append(load(path))

static func pose(state:Dictionary,reduced:bool=false) -> Dictionary:
	var t:float=state.time
	var target:Vector2=state.position
	var belt:bool=state.get("kind","belt")=="belt"
	var contact:Vector2=target+Vector2(-12,9) if belt else target+Vector2(-18,20)
	# Billy works below the belt. The thief uses the far side and returns left.
	var lane_y:float=92.0 if belt else contact.y+55.0
	var staging:=Vector2(contact.x,lane_y)
	var entrance:=Vector2(-35,lane_y)
	var feet:Vector2=entrance.lerp(staging,clampf(t/1.55,0,1))
	var kind:String="run"
	var facing:float=1.0
	var still:bool=false
	if t>=1.55 and t<1.75:
		feet=staging.lerp(contact,smoothstep(0,1,(t-1.55)/0.2))
	elif t>=1.75 and t<2.65:
		kind="sit"
		feet=contact
	elif t>=2.65 and t<3.25:
		kind="carry"
		feet=contact
		still=true
	elif t>=3.25:
		kind="carry"
		facing=-1.0
		var escape:=Vector2(maxf(contact.x,100.0),185.0)
		feet=contact.lerp(escape,clampf((t-3.25)/0.45,0,1)) if t<3.7 else escape.lerp(Vector2(-55,185),clampf((t-3.7)/(DURATION-3.7),0,1))
	var index:int=0 if reduced or still else int(t*9)%4
	if kind=="sit": index=clampi(int((t-1.75)/0.9*5),0,4)
	if kind=="jump": index=clampi(int((t-1.55)/0.8*5),0,4)
	if kind=="jump" and not state.get("taken",false):
		kind="jump_empty"
		index=mini(index,3)
	var hop:float=t-float(state.get("hop_start",-100.0))
	if hop>=0.0 and hop<0.7:
		kind="jump" if state.get("taken",false) else "jump_empty"
		index=clampi(int(hop/0.7*(5 if kind=="jump" else 4)),0,4 if kind=="jump" else 3)
		feet.y-=sin(PI*hop/0.7)*58.0
	# Clear the foreground crates before leaving the viewport. Start in open space
	# and land fully offscreen; preserve an overlapping Billy jump without adding heights.
	if t>=3.7 and feet.x<90.0:
		var exit_jump:float=clampf((90.0-feet.x)/145.0,0.0,1.0)
		kind="jump" if state.get("taken",false) else "jump_empty"
		index=clampi(int(exit_jump*(5 if kind=="jump" else 4)),0,4 if kind=="jump" else 3)
		feet.y=minf(feet.y,185.0-sin(PI*exit_jump)*78.0)
	return {"feet":feet,"kind":kind,"index":index,"facing":facing}

static func belt_gap(state:Dictionary) -> float:
	if state.is_empty() or state.get("kind","")!="belt" or not state.get("taken",false): return 0.0
	return 1.0-smoothstep(BELT_SLIDE_START,BELT_SLIDE_END,float(state.time))

static func should_jump(previous:Vector2,feet:Vector2,worker:Vector2,worker_velocity:Vector2,delta:float) -> bool:
	if delta<=0.0 or worker_velocity.length()<1.0: return false
	var relative:=feet-worker
	var velocity:Vector2=(feet-previous)/delta-worker_velocity
	if relative.length()>maxf(85.0,velocity.length()*0.28+30.0) or relative.dot(velocity)>=0.0: return false
	var closest:float=clampf(-relative.dot(velocity)/maxf(velocity.length_squared(),1.0),0.0,0.28)
	return (relative+velocity*closest).length()<30.0

static func draw(canvas:Node2D,state:Dictionary,reduced:bool) -> void:
	if state.is_empty(): return
	prepare()
	var p:=pose(state,reduced)
	canvas.draw_set_transform(p.feet,0.0,Vector2(p.facing,1.0))
	var texture:Texture2D=frames[p.kind][p.index]
	# All frames share head scale; taller poses retain their natural proportions.
	var head_offset:float=22.0 if p.kind=="jump_empty" and p.index==0 else 0.0
	canvas.draw_texture_rect(texture,Rect2(Vector2(-22,-44-head_offset*44.0/256.0),texture.get_size()*44.0/256.0),false)
	if state.get("taken",false):
		var color:int=state.color
		var rect:Rect2=Cargo.draw_rect(color)
		rect.position*=0.75
		rect.size*=0.75
		var hand_y:float=-23.0
		if p.kind=="sit": hand_y=[-23.0,-15.0,-5.0,-13.0,-23.0][p.index]
		rect.position+=Vector2(14,hand_y)
		canvas.draw_texture_rect(Cargo.get_texture(color),rect,false)
	canvas.draw_set_transform(Vector2.ZERO)
