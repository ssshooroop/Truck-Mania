extends SceneTree
const Main=preload("res://scripts/main.gd")
var game
var failures=0
var checked=0
var blocked=0
func _initialize(): run.call_deferred()
func check(ok:bool,message:String):
 if not ok:
  failures+=1
  push_error(message)
func click(id:int):
 var event=InputEventMouseButton.new()
 event.button_index=MOUSE_BUTTON_LEFT
 event.pressed=true
 event.position=game.get_global_transform_with_canvas()*game._world_transform()*game.bus_visuals[id].position
 game._input(event)
func run():
 game=Main.new()
 game.automation=true
 game.save_enabled=false
 root.add_child(game)
 game.sound_enabled=false
 for height in [720,1171]:
  root.size=Vector2i(540,height)
  await process_frame
  for level in game.model.level_count():
   game._load_level(level)
   for bus in game.model.buses:
    checked+=1
    check(game._truck_at(bus.position)==bus.id,"Hit target mismatch level %d truck %d height %d"%[level+1,bus.id,height])
    if not game.model.blocking_ids(bus.id).is_empty(): blocked+=1
  for activity in ["loading","arrival","pending"]:
   game._load_level(28)
   await process_frame
   await process_frame
   var origin:Vector2=game.bus_visuals[5].position
   var before:Dictionary=game.model.snapshot()
   check(game._maneuver_arrival(5).is_empty(),"Red truck must bump")
   game.loading=true
   if activity=="arrival": game.arrival_ids[999]=true
   if activity=="pending":
    game.road_busy=true
    click(5)
    check(game.pending_dispatch==5,"Busy road retains click")
    game.road_busy=false
    game._process_pending_dispatch()
   else: click(5)
   check(game.road_busy and game.pending_dispatch==-1,"Immediate bump during "+activity)
   await create_timer(0.1).timeout
   check(game.bus_visuals[5].position.distance_to(origin)>0.5,"Visible motion during "+activity)
   game._open_settings()
   var paused:Vector2=game.bus_visuals[5].position
   await create_timer(0.08).timeout
   check(game.bus_visuals[5].position==paused,"Bump pauses")
   game._resume()
   while game.road_busy: await process_frame
   check(game.bus_visuals[5].position==origin,"Returns to origin")
   check(game.model.snapshot()==before and game.moves==0 and game.history.is_empty(),"No gameplay change on blocked click")
   check(game.loading,"Worker state preserved")
   game._load_level(28)
   game.loading=true
   click(5)
   game._load_level(0)
   await create_timer(0.1).timeout
   check(not game.road_busy and game.impact.is_empty(),"Restart cancels feedback")
 print("Input audit: %d trucks, %d blocked, 100 levels x phone/tablet; failures=%d"%[checked,blocked,failures])
 quit(0 if failures==0 else 1)

