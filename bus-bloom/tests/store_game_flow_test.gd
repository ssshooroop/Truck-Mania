extends SceneTree
## Real game/store integration; only the external Huawei SDK is mocked.
## Every save stays in a unique artifacts directory, never in user://.
const Game = preload("res://scripts/main.gd")
var checks := 0
var failures := 0
var services:Array = []

class MockNative extends RefCounted:
	signal env_ready(ok:bool,error:String)
	signal products_loaded(payload:String,error:String)
	signal purchase_verified(payload:String)
	signal operation_finished(request_id:int,status:String,error:String)
	signal consumed(token:String,ok:bool,error:String)
	var save_path := ""
	var purchases:Array = []
	var restores:Array = []
	var confirmations:Array = []
	var snapshots:Array = []
	func initialize(_app_id:String,_public_key:String,_catalog:String) -> void: pass
	func query_products() -> void: pass
	func purchase(id:String,ticket:int) -> void: purchases.append([id,ticket])
	func restore(ticket:int) -> void: restores.append(ticket)
	func confirm_delivery(token:String) -> void:
		# Observe disk at the exact point the game permits consumption.
		var saved := ConfigFile.new()
		var error := saved.load(save_path)
		confirmations.append(token)
		snapshots.append({"token":token,"error":error,
			"coins":saved.get_value("economy","coins",-1),
			"state":saved.get_value("economy","state",{}),
			"temporary_exists":FileAccess.file_exists(save_path+".tmp")})

func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _initialize() -> void: run.call_deferred()

func frames(count:int=2) -> void:
	for i in count: await process_frame

func token_key(token:String) -> String: return ("huawei:"+token).sha256_text()
func order_key(order_id:String) -> String: return ("huawei:order:"+order_id).sha256_text()

func receipt(id:String,ticket:int,token:String,source:String="purchase",order_id:String="") -> Dictionary:
	return {"id":id,"token":token,"order_id":order_id if not order_id.is_empty() else "order-"+token,
		"type":1 if id=="starter" else 0,"source":source,"request_id":ticket}

func saved_config(path:String) -> ConfigFile:
	var value := ConfigFile.new()
	check(value.load(path)==OK,"Test progress config can be read")
	return value

func create_game(path:String,reload:bool=false) -> Array:
	var game = Game.new()
	game.automation = true
	game.save_enabled = false
	game.save_path = path
	root.add_child(game)
	game.save_enabled = true
	if reload: game._load_save()
	game.economy.state.intro_seen = true
	game.intro_delays.clear()
	game._show_road_menu(false)
	var native := MockNative.new()
	native.save_path = path
	game.store.initialization_timeout_seconds = 0.2
	game.store.products_timeout_seconds = 0.2
	game.store.operation_timeout_seconds = 0.5
	services.append(game.store)
	check(game.store.initialize(native,{"app_id":"test-app","public_key":"test-key","product_ids":{
		"coins_500":"test.coins500","coins_1200":"test.coins1200","starter":"test.starter"}}),
		"Real StoreService initializes with the native test adapter")
	native.env_ready.emit(true,"")
	await frames()
	native.products_loaded.emit(JSON.stringify([
		{"id":"coins_500","product_id":"test.coins500","type":0,"price":"49,99 TL"},
		{"id":"coins_1200","product_id":"test.coins1200","type":0,"price":"99,99 TL"},
		{"id":"starter","product_id":"test.starter","type":1,"price":"29,99 TL"}]),"")
	await frames()
	check(not game.store.simulate and game.store.is_available("coins_500"),"Integration uses fetched native metadata, never fake-store delivery")
	return [game,native]

func start_purchase(game,native:MockNative,id:String="coins_500") -> int:
	game.overlay = "road_menu"
	game._open_shop(["road_menu"])
	var before := native.purchases.size()
	check(game.modal.tap("buy:"+id),"Available product starts checkout from its shop control")
	check(native.purchases.size()==before+1,"Exactly one native checkout starts")
	return int(native.purchases.back()[1]) if native.purchases.size()>before else -1

func check_persisted(native:MockNative,payment:Dictionary,expected_coins:int) -> void:
	check(not native.snapshots.is_empty(),"Saved delivery reaches native confirmation")
	if native.snapshots.is_empty(): return
	var snapshot:Dictionary = native.snapshots.back()
	var state:Dictionary = snapshot.state
	check(snapshot.error==OK and snapshot.coins==expected_coins,"Balance is committed on disk before native consumption")
	check(state.get("iap_transactions",{}).get(token_key(payment.token))==payment.id,
		"Receipt deduplication is committed before native consumption")
	check(state.get("iap_orders",{}).get(order_key(payment.order_id))==payment.id,
		"Order deduplication is committed before native consumption")
	check(not snapshot.temporary_exists,"Successful commit replaces the target and leaves no temporary file")

func run() -> void:
	root.size = Vector2i(540,1171)
	var original_mute := AudioServer.is_bus_mute(0)
	var directory := "res://artifacts/store-game-flow-%d-%d" % [OS.get_process_id(),Time.get_ticks_usec()]
	check(DirAccess.make_dir_recursive_absolute(directory)==OK,"Dedicated test save directory is created")
	var path := directory+"/progress.cfg"
	var pair:Array = await create_game(path)
	var game = pair[0]
	var native:MockNative = pair[1]
	game.coins = 27
	check(game._save(),"Initial progress can be committed")
	game.coins = 31
	check(game._save(),"Atomic save overwrites an existing progress file")
	check(saved_config(path).get_value("economy","coins")==31,"Atomic overwrite stores the latest complete balance")
	check(not FileAccess.file_exists(path+".tmp"),"Atomic overwrite removes its temporary file")

	# Cancellation must restore presentation state without a grant or receipt.
	AudioServer.set_bus_mute(0,false)
	var ticket := start_purchase(game,native)
	var shown = game.modal
	check(paused and game.store_presenting and shown.input_locked and AudioServer.is_bus_mute(0),
		"Checkout pauses gameplay, locks modal input and mutes game audio")
	check(not shown.tap("close") and not shown.tap("buy:coins_1200"),"Native checkout blocks close and competing purchase taps")
	game._back()
	game._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check(game.modal==shown and not shown.is_closing(),"Back and background notifications cannot replace checkout UI")
	native.operation_finished.emit(ticket,"cancelled","")
	await frames()
	check(game.coins==31 and native.confirmations.is_empty(),"Cancellation grants and consumes nothing")
	check(not paused and not game.store_presenting and not shown.input_locked and not AudioServer.is_bus_mute(0),
		"Cancellation restores gameplay, modal input and prior unmuted audio")
	check(game.overlay=="road_menu" and shown.busy.is_empty() and shown.flash_text=="Покупка отменена",
		"Cancellation restores the original overlay and clears the busy control")
	paused = true
	AudioServer.set_bus_mute(0,true)
	ticket = start_purchase(game,native)
	native.operation_finished.emit(ticket,"cancelled","")
	await frames()
	check(paused and AudioServer.is_bus_mute(0) and not game.modal.input_locked,
		"Checkout preserves a pre-existing pause and audio mute")
	paused = false
	AudioServer.set_bus_mute(0,false)

	# A real verified receipt is persisted before any consume acknowledgement.
	ticket = start_purchase(game,native)
	var first := receipt("coins_500",ticket,"first")
	native.purchase_verified.emit(JSON.stringify(first))
	await frames()
	check(game.coins==531 and game._modal_is("received"),"Verified checkout grants the pack and displays the receipt")
	check(not paused and not game.store_presenting and not game.modal.input_locked,
		"Successful checkout releases presentation state")
	check_persisted(native,first,531)
	var duplicate := receipt("coins_500",0,"first","recovery")
	native.purchase_verified.emit(JSON.stringify(duplicate))
	await frames()
	check(game.coins==531 and native.confirmations.size()==2,"Repeated saved token is acknowledged without another grant")
	var rotated := receipt("coins_500",0,"rotated-token","recovery",first.order_id)
	native.purchase_verified.emit(JSON.stringify(rotated))
	await frames()
	check(game.coins==531 and native.confirmations.size()==3,"The same order with another token cannot grant twice")

	# Once-only bundles persist all items and reject fresh receipts for another grant.
	ticket = start_purchase(game,native,"starter")
	var starter := receipt("starter",ticket,"starter-first")
	native.purchase_verified.emit(JSON.stringify(starter))
	await frames()
	check(game.coins==1131 and game.economy.state.inventory.get("extra_slot")==3 and game.economy.state.inventory.get("undo")==5,
		"Starter bundle grants its complete configured contents")
	check("starter" in game.economy.state.purchases,"Bundle ownership is recorded")
	check_persisted(native,starter,1131)
	var inventory:Dictionary = game.economy.state.inventory.duplicate(true)
	var again := receipt("starter",0,"starter-second","recovery")
	native.purchase_verified.emit(JSON.stringify(again))
	await frames()
	check(game.coins==1131 and game.economy.state.inventory==inventory,
		"An already-owned bundle cannot grant again under a new order")
	check_persisted(native,again,1131)
	game._open_shop(["road_menu"])
	check(not game.modal.tap("buy:starter"),"Owned bundle is absent from checkout controls")

	# Reload a fresh game instance, then replay both token and order identities.
	game.store._disconnect_bridge()
	game.save_enabled = false
	game.queue_free()
	await frames()
	pair = await create_game(path,true)
	game = pair[0]
	native = pair[1]
	check(game.coins==1131 and game.economy.state.inventory==inventory and "starter" in game.economy.state.purchases,
		"Balance, bundle inventory and ownership survive a complete game reload")
	native.purchase_verified.emit(JSON.stringify(duplicate))
	native.purchase_verified.emit(JSON.stringify(rotated))
	native.purchase_verified.emit(JSON.stringify(again))
	await frames()
	check(game.coins==1131 and game.economy.state.inventory==inventory and native.confirmations.size()==3,
		"Persisted token, order and once-only deduplication survive reload")

	# A write failure rolls back everything and never consumes ownership.
	var before_state:Dictionary = game.economy.state.duplicate(true)
	var before_file := FileAccess.get_file_as_bytes(path)
	game.save_path = directory+"/missing-parent/progress.cfg"
	ticket = start_purchase(game,native,"coins_1200")
	var recoverable := receipt("coins_1200",ticket,"save-failure")
	var confirmations_before := native.confirmations.size()
	native.purchase_verified.emit(JSON.stringify(recoverable))
	await frames()
	check(game.coins==1131 and game.economy.state==before_state,"Failed persistence rolls back balance, inventory and both ledgers")
	check(native.confirmations.size()==confirmations_before,"Failed persistence never consumes the payment")
	check(FileAccess.get_file_as_bytes(path)==before_file,"Failed write leaves the previous complete save intact")
	check(not paused and not game.store_presenting and not game.modal.input_locked,
		"Failed delivery restores gameplay and input")
	check(game.modal.flash_text=="Не удалось сохранить покупку. Восстановление будет повторено при следующем запуске.",
		"Failed delivery explains that recovery will retry")
	game.save_path = path
	recoverable.source = "recovery"
	recoverable.request_id = 0
	native.purchase_verified.emit(JSON.stringify(recoverable))
	await frames()
	check(game.coins==2331 and native.confirmations.size()==confirmations_before+1,
		"Unconsumed payment grants once when persistence becomes available")
	check_persisted(native,recoverable,2331)
	native.purchase_verified.emit(JSON.stringify(recoverable))
	await frames()
	check(game.coins==2331,"Recovered receipt remains idempotent")

	# Restoration can mix new consumables and already-delivered bundles.
	game._open_shop(["road_menu"])
	check(game.modal.tap("restore"),"Restore starts from the real shop control")
	ticket = int(native.restores.back())
	var restored := receipt("coins_500",ticket,"restore-coins","restore")
	var restored_bundle := receipt("starter",ticket,"starter-first","restore")
	native.purchase_verified.emit(JSON.stringify(restored))
	native.purchase_verified.emit(JSON.stringify(restored_bundle))
	native.operation_finished.emit(ticket,"restored","")
	await frames()
	check(game.coins==2831 and game.economy.state.inventory==inventory,"Restore grants only previously undelivered consumables")
	check(game._modal_is("shop") and game.modal.flash_text=="Покупки восстановлены",
		"Restore success remains visible after the shop refresh")
	check(not paused and not game.store_presenting and not game.modal.input_locked,"Restore releases presentation and input locks")
	check(saved_config(path).get_value("economy","coins")==2831,"Restored balance is persisted")
	check(game.modal.tap("restore"),"Restore can be invoked again after completion")
	native.operation_finished.emit(int(native.restores.back()),"restored","")
	await frames()
	check(game.modal.flash_text=="Нет покупок для восстановления" and game.coins==2831,
		"An empty restore shows truthful feedback without granting anything")

	game.save_enabled = false
	game.store._disconnect_bridge()
	game.queue_free()
	await frames()
	# Finish mock watchdogs while their services still exist.
	await create_timer(0.55).timeout
	services.clear()
	AudioServer.set_bus_mute(0,original_mute)
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(directory)
	print("STORE_GAME_FLOW: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
