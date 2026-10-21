extends SceneTree
const Game=preload("res://scripts/main.gd")
var failures:=0
func check(ok:bool,label:String):
 if not ok:
  failures+=1
  push_error(label)
func _initialize(): _run.call_deferred()
func _run():
 root.size=Vector2i(540,1171)
 var g=Game.new()
 g.save_enabled=false
 g.automation=true
 root.add_child(g)
 g.speed_factor=0.03
 for level in g.model.level_count():
  g._load_level(level)
  for b:Dictionary in g.model.buses:
   check(g._truck_at(b.position)==b.id,"Tap center level %d id %d"%[level+1,b.id])
 g._load_level(1)
 var ev=InputEventMouseButton.new()
 ev.button_index=MOUSE_BUTTON_LEFT
 ev.pressed=true
 ev.position=g.model.buses[0].position
 g._input(ev)
 check(g.model.buses[0].status=="arriving","Green truck reacts to event position independently of cursor")
 ev.position=g.model.buses[3].position
 g._input(ev)
 check(g.pending_dispatch==3,"Tap while driving is remembered")
 var until=Time.get_ticks_msec()+5000
 while (g.road_busy or g.pending_dispatch>=0) and Time.get_ticks_msec()<until: await process_frame
 check(g.pending_dispatch==-1 and g.model.buses[3].status!="yard","Remembered truck starts automatically")
 g._load_level(1)
 var start:Vector2=g.bus_visuals[9].position
 g._dispatch(9)
 await process_frame
 check(g.road_busy,"Blocked green truck starts bump feedback")
 until=Time.get_ticks_msec()+5000
 while g.road_busy and Time.get_ticks_msec()<until: await process_frame
 check(g.bus_visuals[9].position.is_equal_approx(start),"Blocked truck returns to start")
 g.road_busy=true
 g._dispatch(0)
 g._load_level(0)
 check(g.pending_dispatch==-1,"Restart clears pending input")
 g._load_level(1)
 await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://artifacts/compact-level-2.png")
 print("Tap regression: ",failures," failures")
 quit(1 if failures else 0)
