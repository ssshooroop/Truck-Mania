extends BaseButton
const Style = preload("res://scripts/ui/modal_style.gd")
var icon:Texture2D
var shine := false
var reduced_motion := false
var age := 0.0
func _ready():
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
func _process(delta:float):
	if not reduced_motion: age += delta
	queue_redraw()
func _draw():
	var center := size*0.5
	if shine: Style.rays(self,center,size.x*0.58,age*0.35)
	Style.icon(self,icon,center+Vector2(0,2 if button_pressed else 0),size.x*0.85)
