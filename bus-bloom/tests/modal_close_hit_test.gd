extends SceneTree
const Modal=preload("res://scripts/ui/game_modal.gd")
const Catalog=preload("res://scripts/ui/modal_catalog.gd")
var actions:Array=[]
func _initialize(): run.call_deferred()
func run():
	for viewport in [Vector2(540,720),Vector2(540,1171)]:
		for spec in [Catalog.offer("undo",20,50,false),Catalog.offer("extra_slot",100,50,true),Catalog.shortfall(100,20,25,false),Catalog.ad_reward("offer",25,50)]:
			for header in [false,true]:
				var modal=Modal.new(spec)
				root.add_child(modal)
				modal.set_anchors_preset(Control.PRESET_TOP_LEFT)
				modal.size=viewport
				modal.age=1.0
				modal._layout()
				modal.action.connect(func(id):actions.append(id);modal.close())
				var point:Vector2=modal._close_center()
				if not header:
					for item in modal.placed:
						if item.block.get("id","")=="close": point=item.rect.get_center()
				assert(modal._hit(point)=="close","Visible close control must be clickable")
				actions.clear()
				for down in [true,false]:
					var event=InputEventMouseButton.new()
					event.button_index=MOUSE_BUTTON_LEFT
					event.pressed=down
					event.position=modal.base*point
					modal._gui_input(event)
				assert(actions==["close"] and modal.is_closing())
				modal.queue_free()
				await process_frame
	print("PASS: actual press/release closes footer and header on 4 modal types, phone/tablet")
	quit()
