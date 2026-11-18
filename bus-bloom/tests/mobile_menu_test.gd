extends SceneTree
const Main=preload("res://scripts/main.gd")
var failures=0
func _initialize(): run.call_deferred()
func check(ok:bool,message:String):
 if not ok:
  failures+=1
  push_error(message)
func run():
 var game=Main.new()
 game.automation=true
 game.save_enabled=false
 root.add_child(game)
 game.sound_enabled=false
 for height in [1171,720]:
  root.size=Vector2i(540,height)
  await create_timer(0.08).timeout
  game._show_road_menu(false)
  game.road_menu.configure(100,0,false,false)
  await create_timer(0.2).timeout
  var menu=game.road_menu
  check(menu.coin_badge.position.x>menu.size.x/2,"Balance on right")
  check(menu.language_button.position.y>menu.coin_badge.position.y+menu.coin_badge.size.y,"Controls below balance")
  check(menu.preference_icons.music.position.y==menu.language_button.position.y,"Columns aligned")
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://artifacts/menu-mobile-%d.png"%height)
  menu.road.snap_enabled=false
  menu.road.scroll=0.0
  await create_timer(0.08).timeout
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png('res://artifacts/menu-seam-%d.png'%height)
  game._load_level(28)
  game._open_settings()
  await create_timer(0.3).timeout
  check(game._modal_is("pause"),"Modern pause window")
  var was=game.music_enabled
  game.modal.tap("music")
  check(game.music_enabled!=was and game.overlay=="settings","Toggle stays paused")
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://artifacts/pause-mobile-%d.png"%height)
  game.modal.tap("resume")
  check(game.overlay=="" and game.modal==null,"Resume closes pause")
  game._open_settings()
  await create_timer(0.08).timeout
  game.modal.tap("retry")
  check(game.overlay=="" and game.moves==0,"Retry starts level")
  game._open_settings()
  await create_timer(0.08).timeout
  game.modal.tap("menu")
  check(game.overlay=="road_menu","Menu returns to road")
 print("Mobile menu and pause failures: ",failures)
 quit(0 if failures==0 else 1)

