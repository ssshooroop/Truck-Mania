extends SceneTree
const Game = preload("res://scripts/main.gd")
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	root.size = Vector2i(540,1171)
	var game = Game.new()
	root.add_child(game)
	game.automation = true
	game.save_enabled = false
	game._sync_audio_preferences()
	game._load_level(4)
	var bus = game.model.buses[3]
	bus.status = "arriving"
	for pose in [
		{"name":"left","point":Vector2(-140,800),"angle":0.0},
		{"name":"turn","point":Vector2(-140,800),"angle":PI/4},
		{"name":"bottom","point":Vector2(270,1220),"angle":PI/2}
	]:
		game.bus_visuals[bus.id] = {"position":pose.point,"angle":pose.angle}
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/edge-"+pose.name+".png")
	game.free()
	await create_timer(0.35).timeout
	quit()
