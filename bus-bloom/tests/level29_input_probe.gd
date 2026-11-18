extends SceneTree
const Main=preload("res://scripts/main.gd")
func _initialize(): run.call_deferred()
func run():
 var game=Main.new()
 game.automation=true
 game.save_enabled=false
 root.add_child(game)
 game.sound_enabled=false
 game._load_level(28)
 await create_timer(1.5).timeout
 for bus in game.model.buses:
  print("TRUCK ",bus.id," color=",bus.color," pos=",bus.position," angle=",rad_to_deg(bus.angle)," hit=",game._truck_at(bus.position)," blockers=",game.model.blocking_ids(bus.id)," contact=",game.Contact.contact(game.model,bus.id))
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://artifacts/level29-input.png")
 var stamp=Time.get_ticks_msec()
 var route=game._maneuver_arrival(5)
 print('RED_ROUTE ms=',Time.get_ticks_msec()-stamp,' poses=',route.size())
 game.loading=true
 game._dispatch(5)
 print('CLICK loading: pending=',game.pending_dispatch,' road=',game.road_busy,' status=',game.model.get_bus(5).status)
 await create_timer(0.15).timeout
 print('AFTER150ms position=',game.bus_visuals[5].position)
 quit()

