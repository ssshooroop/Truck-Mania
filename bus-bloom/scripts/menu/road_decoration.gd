extends Node2D

# Images baked from the user's props.blend; no runtime 3D.
const TEXTURES = [
 preload("res://assets/artwork/menu/props-rendered/tree-wide.png"),
 preload("res://assets/artwork/menu/props-rendered/tree-tall.png"),
 preload("res://assets/artwork/menu/props-rendered/tree-round.png"),
 preload("res://assets/artwork/menu/props-rendered/sign.png"),
 preload("res://assets/artwork/menu/props-rendered/sign-alt.png"),
 preload("res://assets/artwork/menu/props-rendered/traffic-light.png")
]
const SIZES = [Vector2(145,182),Vector2(123,195),Vector2(140,178),Vector2(62,126),Vector2(70,126),Vector2(64,160)]
const REGIONS = [Rect2(99,69,189,224), Rect2(134,65,116,228), Rect2(125,61,134,232), Rect2(149,64,81,226), Rect2(149,51,81,239), Rect2(179,60,30,231)]
const CELL_STEP = 0.125
const CELL_COUNT = 14
const MEMBERS_PER_CELL = 3
@export_enum("Wide tree","Tall tree","Round tree","No-entry sign","Yield sign","Traffic light") var kind: int = 0
var world = 0.0
var lateral = 0.22
var size_factor = 1.0
var enabled = true

static func cell_members(cell:int) -> Array:
 var rng = RandomNumberGenerator.new()
 rng.seed = cell*7919+41017
 var tree = rng.randf()<0.72
 var side = -1.0 if rng.randf()<0.5 else 1.0
 var count = rng.randi_range(2,3) if tree and rng.randf()<0.44 else 1
 var phase = rng.randf_range(-0.016,0.016)
 var members = []
 for i in count:
  members.append({"kind":rng.randi_range(0,2) if tree else rng.randi_range(3,5),
   "world":cell*CELL_STEP+phase+(i-(count-1)*0.5)*0.034,
   "side":side,"offset":rng.randf(),"size":rng.randf_range(0.78,1.17) if tree else 1.0})
 return members

func drawn_size() -> Vector2:
 var source:Rect2 = REGIONS[kind]
 return source.size*minf(SIZES[kind].x/source.size.x,SIZES[kind].y/source.size.y)

func _draw() -> void:
 var drawn = drawn_size()
 draw_set_transform(Vector2.ZERO,0,Vector2(1,0.3))
 draw_circle(Vector2(2,0),minf(29,drawn.x*0.28),Color(0.08,0.28,0.15,0.15))
 draw_set_transform(Vector2.ZERO)
 draw_texture_rect_region(TEXTURES[kind],Rect2(Vector2(-drawn.x*0.5,-drawn.y),drawn),REGIONS[kind])
