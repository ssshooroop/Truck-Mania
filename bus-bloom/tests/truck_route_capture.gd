extends SceneTree
const Game=preload("res://scripts/main.gd")
func _initialize(): _run.call_deferred()
func _run():
 root.size=Vector2i(540,1171)
 var g=Game.new()
 g.save_enabled=false
 g.automation=true
 root.add_child(g)
 g._load_level(1)
 var b:Dictionary=g.model.buses[3]
 var planner=g.TruckRoute.new()
 planner.setup(g,3)
 var path:Array=planner.plan(b.position,b.angle,g._bay_position(0,b.kind),g.BAY_ANGLE)
 var trail:=Node2D.new()
 g.add_child(trail)
 trail.draw.connect(func():
  var points:=PackedVector2Array()
  for pose:Dictionary in path: points.append(pose.position)
  trail.draw_polyline(points,Color(1,0.8,0.05,0.85),3,true))
 trail.queue_redraw()
 await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://artifacts/short-route-preview.png")
 trail.hide()
 g._dispatch(3)
 await create_timer(0.6).timeout
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://artifacts/short-route-moving.png")
 var deadline:=Time.get_ticks_msec()+12000
 while g.road_busy and Time.get_ticks_msec()<deadline: await process_frame
 print("NATIVE_ROUTE_COMPLETE status=",g.model.buses[3].status)
 quit()
