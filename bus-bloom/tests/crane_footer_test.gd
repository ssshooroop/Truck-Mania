extends SceneTree
func _initialize(): run.call_deferred()
func run():
	var g=preload("res://scripts/main.gd").new()
	g.automation=true
	g.save_enabled=false
	root.add_child(g)
	g._load_level(14)
	g._cancel_animation()
	g.overlay=""
	g.intro_age=10
	g.economy.state.crane_intro_used=false
	assert(g._footer_buttons()==[0,1,2])
	g._open_crane_offer()
	assert(g.modal==null)
	g.economy.state.crane_intro_used=true
	assert(g._footer_buttons()==[0,1,3,2])
	if "--visual" in OS.get_cmdline_user_args():
		root.size=Vector2i(540,720)
		g.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/crane-footer.png")
	assert(g._can_rescue("crane"))
	var before:int=g.coins
	g._open_crane_offer()
	assert(g.modal.spec.id=="offer_crane")
	assert(g.coins==before)
	g.modal.action.emit("close")
	g._close_modal(true)
	g.coins=300
	g._open_crane_offer()
	g.modal.action.emit("buy")
	assert(g.coins==150 and g.model.bays[0]>=0)
	assert(g.model.open_bay_count==3)
	assert(not g._can_rescue("crane"))
	g._load_level(0)
	g._cancel_animation()
	assert(g._footer_buttons()==[0,1,3,2])
	assert(not g._can_rescue("crane"))
	g.queue_free()
	await process_frame
	print("Crane footer: hidden before onboarding, persistent unlock, confirmation, payment, free bay and busy gate passed")
	quit()
