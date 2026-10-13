extends SceneTree
const Game = preload("res://scripts/main.gd")
const Audio = preload("res://scripts/game_audio.gd")
var checks = 0
var failures = 0
func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	root.size = Vector2i(540,1171)
	var game = Game.new()
	root.add_child(game)
	game.automation = true
	game.save_path = "res://artifacts/audio-test-settings.cfg"
	game.save_enabled = true
	for key in ["music","sound","vibration"]: game._set_preference(key,true)
	game._show_road_menu(false)
	var menu = game.road_menu
	menu.preference_icons.music.button_pressed = false
	check(not game.music_enabled and game.sound_enabled and game.vibration_enabled,"Note toggles only music")
	menu.preference_icons.sound.button_pressed = false
	check(not game.sound_enabled and game.vibration_enabled,"Speaker toggles effects independently")
	menu.preference_icons.vibration.button_pressed = false
	check(not game.vibration_enabled,"Vibration is independent")
	game.music_enabled = true
	game.sound_enabled = true
	game.vibration_enabled = true
	game._load_save()
	check(not game.music_enabled and not game.sound_enabled and not game.vibration_enabled,"All preferences survive save and reload")
	check(menu.find_children("*","Label",true,false).is_empty(),"Main menu has no text labels")
	check(is_equal_approx(menu.road.get_rect().end.y,menu.size.y),"Road reaches the bottom without a panel")
	game.save_enabled = false
	DirAccess.remove_absolute(game.save_path)
	var audio = Audio.new()
	root.add_child(audio)
	audio.music.volume_db = -80
	for player in audio.voices: player.volume_db = -80
	audio.set_context("menu")
	check(audio.music.stream==Audio.MUSIC.menu and audio.music.playing,"Menu music is selected")
	audio.set_context("game")
	check(audio.music.stream==Audio.MUSIC.game and audio.music.playing,"Gameplay selects its own music")
	audio.set_preferences(false,true)
	check(not audio.music.playing and audio.effects_enabled,"Music mute preserves effects")
	for material_id in 6:
		audio.pickup(material_id)
		check(audio.voices[(audio.next_voice+9)%10].stream==Audio.PICKUP[material_id],"Pickup uses the correct material clip")
	audio.stop_effects()
	for count in [1,3,4,6]:
		audio.deposit(count)
		var key = "one" if count==1 else "four" if count==4 else "many"
		check(audio.voices[(audio.next_voice+9)%10].stream==Audio.FX[key],"Batch chooses its matching upload clip")
	audio.stop_effects()
	audio.deposit(2)
	var pair = audio.voices[(audio.next_voice+9)%10]
	check(audio.repeat_left[pair]==1,"Two-item clip is scheduled twice")
	var deadline = Time.get_ticks_msec()+5000
	while audio.repeat_left.get(pair,-1)==1 and Time.get_ticks_msec()<deadline:
		await create_timer(0.05).timeout
	check(pair.playing and audio.repeat_left.get(pair,-1)==0,"Second playback occurs after the first finishes")
	audio.set_preferences(false,false)
	check(not pair.playing and audio.repeat_left.is_empty(),"Muting cancels the current and queued effect")
	audio.set_preferences(false,true)
	audio.effect("bump")
	audio.effect("full")
	check(audio.voices[(audio.next_voice+9)%10].stream==Audio.FX.full,"Full-truck sound is routed")
	audio.pause_effects(true)
	check(audio.voices[(audio.next_voice+9)%10].stream_paused,"Settings pause playing effects")
	audio.stop_effects()
	audio.free()
	if "--capture-menu" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/menu-preferences-off.png")
	game.queue_free()
	await create_timer(0.35).timeout
	print("Audio and preferences: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
