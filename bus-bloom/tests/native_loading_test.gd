extends SceneTree
func _initialize(): run.call_deferred()
func run():
 var screen=load("res://scenes/loading_screen.tscn").instantiate()
 screen.automation=true
 root.add_child(screen)
 current_scene=screen
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://artifacts/native-loading.png")
 var deadline=Time.get_ticks_msec()+60000
 while current_scene==screen and Time.get_ticks_msec()<deadline:
  await process_frame
 if current_scene==screen:
  push_error("Loading did not reach game")
  quit(1)
  return
 await create_timer(0.4).timeout
 assert(not is_instance_valid(screen),"Loading cover removed")
 current_scene._cancel_animation()
 current_scene.queue_free()
 await process_frame
 await process_frame
 print("Native loading artwork rendered; game initialized; cover removed")
 quit()

