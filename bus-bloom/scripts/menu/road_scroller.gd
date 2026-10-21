extends Control

const RoadProjection = preload("res://scripts/menu/road_projection.gd")
@export var projection: Resource = RoadProjection.new()
@export var road_texture: Texture2D = preload("res://assets/artwork/menu/road-1.png")
@export var friction: float = 5.0
@export var scroll_speed: float = 1.0
@export var level_spacing: float = 0.19
var scroll: float = 0.25
var velocity: float = 0.0
var dragging = false
var snap_enabled = false
var level_count = 3
var origin = 0.25
var road_material: ShaderMaterial

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	road_material = ShaderMaterial.new()
	road_material.shader = preload("res://scripts/menu/road.gdshader")
	road_material.set_shader_parameter("road_texture",road_texture)
	material = road_material
	update_material()

func _process(delta:float) -> void:
	if not dragging:
		scroll += velocity*delta
		velocity *= exp(-friction*delta)
		if snap_enabled and absf(velocity)<0.025:
			var index = clampi(roundi((origin-scroll)/level_spacing),0,level_count-1)
			scroll = lerpf(scroll,origin-index*level_spacing,1.0-exp(-12.0*delta))
	update_material()

func update_material() -> void:
	if not road_material: return
	road_material.set_shader_parameter("scroll",fposmod(scroll,1.0))
	road_material.set_shader_parameter("curvature",projection.curvature)
	road_material.set_shader_parameter("span",projection.span)
	road_material.set_shader_parameter("perspective",projection.perspective)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color.WHITE)
