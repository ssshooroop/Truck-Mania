extends SceneTree
const Game=preload("res://scripts/main.gd")
func _initialize():run.call_deferred()
func run():
 root.size=Vector2i(540,1171)
 var g=Game.new()
 root.add_child(g)
 g.save_enabled=false
 g._load_level(5)
 await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://artifacts/compact10-level6.png")
 quit()
