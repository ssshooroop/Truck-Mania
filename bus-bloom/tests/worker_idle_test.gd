extends SceneTree
const Game=preload("res://scripts/main.gd")
var failures=0
func check(ok:bool,label:String):
 if not ok:
  failures+=1
  print("FAIL ",label)
func _initialize(): run.call_deferred()
func run():
 var g=Game.new()
 root.add_child(g)
 g.set_process(false)
 g._load_level(1)
 g._update_worker_idle(4.49)
 check(g.worker_panic_time<0,"threshold")
 g._update_worker_idle(0.01)
 check(g.worker_panic_time>=0,"starts")
 g._update_worker_idle(1.2)
 check(g.worker_position.distance_to(Vector2(24,185))<0.01,"left edge")
 g._update_worker_idle(1.2)
 check(g.worker_position.distance_to(g.WORKER_HOME)<0.01,"right edge")
 for jump in 3:
  g._update_worker_idle(0.225)
  check(g.worker_idle_jump>16.9,"jump apex %d"%jump)
  g._update_worker_idle(0.225)
 check(g.worker_panic_time<0 and g.worker_idle_jump==0,"three jumps finish")
 g._update_worker_idle(4.6)
 var tap=InputEventMouseButton.new()
 tap.pressed=true
 tap.button_index=MOUSE_BUTTON_LEFT
 tap.position=Vector2(530,1150)
 g._input(tap)
 check(g.worker_panic_time<0 and g.worker_position==g.WORKER_HOME,"input cancels")
 for flag in ["loading","busy","road_busy","collecting","reduced_motion"]:
  g.set(flag,true)
  g._update_worker_idle(10)
  check(g.worker_panic_time<0,flag)
  g.set(flag,false)
 g.worker_position=Vector2(150,200)
 g.loading=true
 g._update_worker_idle(10)
 check(g.worker_position==Vector2(150,200),"working worker not teleported")
 g.loading=false
 g.overlay="win"
 g._update_worker_idle(10)
 check(g.worker_panic_time<0,"overlay")
 g.overlay=""
 g._update_worker_idle(5)
 g._load_level(0)
 check(g.worker_panic_time<0 and g.worker_position==g.WORKER_HOME,"level reset")
 print("Worker idle: ",failures," failures")
 quit(1 if failures else 0)
