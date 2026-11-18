extends SceneTree
func _initialize(): run.call_deferred()
func run():
	var roots=JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var count:=0
	for path in roots:
		assert(ResourceLoader.exists(path),"Missing resource: "+path)
		assert(load(path)!=null,"Invalid resource: "+path)
		count+=1
	assert(not ResourceLoader.exists("res://tests/thief_jump_test.gd"))
	assert(not ResourceLoader.exists("res://assets/artwork/builder/run/run1.png"))
	var loc=load("res://scripts/localization.gd")
	for locale in loc.SUPPORTED:
		loc.set_locale(locale)
	var game=load("res://scripts/main.gd").new()
	game.automation=true
	game.save_enabled=false
	root.add_child(game)
	await process_frame
	for level in [0,14,16,18,19,99]:
		game._load_level(level)
		game._cancel_animation()
		await process_frame
	game.queue_free()
	await process_frame
	print("Packed Android data validated: ",count," resources, all languages, levels 1/15/17/19/20/100")
	quit()
