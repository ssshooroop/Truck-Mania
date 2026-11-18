extends SceneTree
const Store = preload("res://scripts/ui/store_service.gd")
var checks := 0
var failures := 0
var deliveries:Array = []
var services:Array = []

class MockNative extends RefCounted:
	signal env_ready(ok:bool,error:String)
	signal products_loaded(payload:String,error:String)
	signal purchase_verified(payload:String)
	signal operation_finished(request_id:int,status:String,error:String)
	signal consumed(token:String,ok:bool,error:String)
	var initialized_with:Array = []
	var catalog:Array = []
	var query_count := 0
	var purchases:Array = []
	var restores:Array = []
	var confirmations:Array = []
	func initialize(app_id:String,public_key:String,payload:String) -> void:
		initialized_with = [app_id,public_key]
		catalog = JSON.parse_string(payload)
	func query_products() -> void: query_count += 1
	func purchase(id:String,ticket:int) -> void: purchases.append([id,ticket])
	func restore(ticket:int) -> void: restores.append(ticket)
	func confirm_delivery(token:String) -> void: confirmations.append(token)

func check(value:bool,message:String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func settings() -> Dictionary:
	return {"app_id":"mock_app","public_key":"mock_key","product_ids":{
		"coins_500":"huawei.coins_500","coins_1200":"huawei.coins_1200","starter":"huawei.starter"}}

func metadata() -> Array:
	return [{"id":"coins_500","product_id":"huawei.coins_500","type":0,"price":"49,99 TL"},
		{"id":"starter","product_id":"huawei.starter","type":1,"price":"29,99 TL"}]

func receipt(id:String,ticket:int,token:String,source:String="purchase") -> Dictionary:
	return {"id":id,"token":token,"order_id":"order-"+token,
		"type":1 if id=="starter" else 0,"source":source,"request_id":ticket}

func create_service():
	var store = Store.new()
	store.initialization_timeout_seconds = 0.2
	store.products_timeout_seconds = 0.2
	store.operation_timeout_seconds = 0.2
	store.simulation_delay_seconds = 0.01
	services.append(store)
	return store

func ready_service() -> Array:
	var store = create_service()
	var native = MockNative.new()
	check(store.initialize(native,settings()),"Configured mock native initializes")
	native.env_ready.emit(true,"")
	await process_frame
	check(native.query_count==1,"Environment readiness queries product details")
	native.products_loaded.emit(JSON.stringify(metadata()),"")
	await process_frame
	return [store,native]

func collect_purchase(store,id:String,box:Array) -> void:
	box.append(await store.purchase(id))

func collect_restore(store,box:Array) -> void:
	box.append(await store.restore())

func wait_result(box:Array,label:String) -> Dictionary:
	var until := Time.get_ticks_msec()+1500
	while box.is_empty() and Time.get_ticks_msec()<until:
		await create_timer(0.01).timeout
	check(not box.is_empty(),label+" resolves within bounded time")
	return box[0] if not box.is_empty() else {}

func run() -> void:
	var absent = create_service()
	check(not absent.is_available() and not absent.can_restore(),"Real store is unavailable without SDK setup")
	check(absent.price("coins_500")=="Недоступно","Real store does not display draft USD")
	check(absent.old_price("starter")=="" and absent.bonus("coins_1200")=="","Real store has no draft discount claims")
	check(absent.coin_packs().size()==5 and absent.pack_for(1000)=="coins_1200","Catalog and coin pack APIs remain compatible")
	check(not absent.initialize(),"Desktop does not silently initialize Huawei or fake store")
	check(not absent.simulate,"Missing SDK never enables simulation")
	var unavailable:Dictionary = await absent.purchase("coins_500")
	check(unavailable.status=="unavailable","Unavailable purchase resolves without payment")
	var bad_native = MockNative.new()
	check(not absent.initialize(bad_native,{}),"Missing configuration fails closed")
	check(bad_native.initialized_with.is_empty(),"Missing configuration never calls native setup")

	var pair:Array = await ready_service()
	var store = pair[0]
	var native = pair[1]
	check(native.catalog.size()==3,"Only registered products are sent to native")
	check(native.catalog[0].type==0 and native.catalog[2].type==1,"Consumable and once-only native types are correct")
	check(store.price("coins_500")=="49,99 TL" and store.is_available("coins_500"),"Only SDK-localized product price enables checkout")
	check(not store.is_available("coins_1200") and not store.is_available("coins_2600"),"Missing metadata and unregistered products stay unavailable")
	check(store.can_restore(),"Restoration is available once environment is ready")
	var empty_id:Dictionary = await store.purchase("")
	check(empty_id.status=="unavailable" and native.purchases.is_empty(),"Empty product ID never reaches native checkout")
	store.delivery_requested.connect(func(value:Dictionary): deliveries.append(value))

	var cancelled:Array = []
	collect_purchase(store,"coins_500",cancelled)
	check(store.buying and not store.is_available("coins_500") and not store.can_restore(),"Active checkout disables new checkout and restore")
	var busy:Dictionary = await store.purchase("starter")
	check(busy.status=="busy" and native.purchases.size()==1,"Concurrent purchase is rejected before another native call")
	var cancelled_ticket:int = native.purchases.back()[1]
	native.operation_finished.emit(cancelled_ticket,"cancelled","")
	var cancelled_result:Dictionary = await wait_result(cancelled,"Cancellation")
	check(cancelled_result.status=="cancelled" and deliveries.is_empty() and native.confirmations.is_empty(),"Cancellation grants and consumes nothing")

	var pending:Array = []
	collect_purchase(store,"coins_500",pending)
	var pending_ticket:int = native.purchases.back()[1]
	native.operation_finished.emit(pending_ticket,"verified","")
	var pending_result:Dictionary = await wait_result(pending,"Receipt-less native success")
	check(pending_result.status=="pending" and deliveries.is_empty(),"Native success alone cannot deliver; timeout is pending")
	check(pending_result.error=="operation_timeout","Timeout does not claim no charge")
	var late:Dictionary = receipt("coins_500",pending_ticket,"late-token")
	native.purchase_verified.emit(JSON.stringify(late))
	await process_frame
	check(deliveries.size()==1 and native.confirmations.is_empty(),"Late verified payment still requests delivery and is not consumed early")
	store.confirm_delivery(deliveries.pop_back(),true)
	check(native.confirmations==["late-token"],"Late payment is acknowledged only after durable confirmation")

	var unpaid:Array = []
	collect_purchase(store,"coins_500",unpaid)
	var save_ticket:int = native.purchases.back()[1]
	var save_receipt:Dictionary = receipt("coins_500",save_ticket,"save-failed-token")
	native.purchase_verified.emit(JSON.stringify(save_receipt))
	native.purchase_verified.emit(JSON.stringify(save_receipt))
	await process_frame
	check(deliveries.size()==1,"Duplicate receipt is deduplicated while delivery is pending")
	check(unpaid.is_empty() and native.confirmations.size()==1,"Verified payment waits for game persistence")
	var modified:Dictionary = deliveries[0].duplicate(true)
	modified.order_id = "wrong-order"
	store.confirm_delivery(modified,true)
	check(native.confirmations.size()==1 and unpaid.is_empty(),"Changed confirmation cannot acknowledge a different receipt")
	store.confirm_delivery(deliveries.pop_back(),false)
	var failed_result:Dictionary = await wait_result(unpaid,"Save failure")
	check(failed_result.status=="failed" and failed_result.error=="delivery_failed","Save failure reports recoverable delivery error")
	check(native.confirmations.size()==1,"Save failure never consumes Huawei ownership")
	var retry:Dictionary = save_receipt.duplicate(true)
	retry.source = "recovery"
	retry.request_id = 0
	native.purchase_verified.emit(JSON.stringify(retry))
	await process_frame
	check(deliveries.size()==1,"Rejected persistence can be retried by owned-purchase recovery")
	store.confirm_delivery(deliveries.pop_back(),true)
	check(native.confirmations.back()=="save-failed-token","Recovered saved grant is acknowledged")

	var success:Array = []
	collect_purchase(store,"starter",success)
	var success_ticket:int = native.purchases.back()[1]
	native.purchase_verified.emit(JSON.stringify(receipt("starter",success_ticket,"starter-token")))
	await process_frame
	store.confirm_delivery(deliveries.pop_back(),true)
	var success_result:Dictionary = await wait_result(success,"Durable purchase")
	check(success_result.status=="delivered" and success_result.delivered_count==1,"Purchase resolves delivered only after game confirms persistence")
	native.consumed.emit("starter-token",false,"network_retry")
	await process_frame
	check(store.last_error=="network_retry","Consumption errors preserve saved delivery and expose retry status")

	var restore_box:Array = []
	collect_restore(store,restore_box)
	var restore_ticket:int = native.restores.back()
	native.purchase_verified.emit(JSON.stringify(receipt("starter",restore_ticket,"restore-a","restore")))
	native.purchase_verified.emit(JSON.stringify(receipt("coins_500",restore_ticket,"restore-b","restore")))
	native.operation_finished.emit(restore_ticket,"restored","")
	await process_frame
	check(deliveries.size()==2 and restore_box.is_empty(),"Restoration waits for all verified deliveries to persist")
	store.confirm_delivery(deliveries.pop_front(),true)
	check(restore_box.is_empty(),"One unfinished restore delivery keeps operation pending")
	store.confirm_delivery(deliveries.pop_front(),true)
	var restored:Dictionary = await wait_result(restore_box,"Restore")
	check(restored.status=="restored" and restored.delivered_count==2,"Restore resolves with delivered count after scan and persistence")
	var empty_restore:Array = []
	collect_restore(store,empty_restore)
	native.operation_finished.emit(native.restores.back(),"restored","")
	var empty_restored:Dictionary = await wait_result(empty_restore,"Empty restore")
	check(empty_restored.status=="empty","An owned scan with no receipts does not invent a restore")
	var forgotten:Dictionary = receipt("coins_500",0,"forgotten-confirmation","recovery")
	var confirmations_before:int = native.confirmations.size()
	native.purchase_verified.emit(JSON.stringify(forgotten))
	await process_frame
	deliveries.clear()
	await create_timer(0.25).timeout
	check(native.confirmations.size()==confirmations_before,"Missing delivery callback never consumes on timeout")
	native.purchase_verified.emit(JSON.stringify(forgotten))
	await process_frame
	check(deliveries.size()==1,"Delivery watchdog permits later recovery after a missing confirmation")
	store.confirm_delivery(deliveries.pop_back(),true)

	var invalids:Array = [receipt("coins_2600",0,"unregistered","recovery"),receipt("coins_500",-1,"negative","recovery")]
	var wrong_type := receipt("starter",0,"type","recovery")
	wrong_type.type = 0
	invalids.append(wrong_type)
	var missing_order := receipt("coins_500",0,"empty","recovery")
	missing_order.order_id = ""
	invalids.append(missing_order)
	for invalid in invalids: native.purchase_verified.emit(JSON.stringify(invalid))
	await process_frame
	check(deliveries.is_empty(),"Unknown SKU, invalid request, wrong type and missing order receipts are rejected")

	var bogus:Array = metadata()
	bogus[0].product_id = "attacker.sku"
	bogus.append({"id":"not_registered","product_id":"unknown","type":0,"price":"0.01"})
	native.products_loaded.emit(JSON.stringify(bogus),"")
	await process_frame
	check(not store.is_available("coins_500") and store.price("coins_500")=="Недоступно","Unrequested SKU metadata cannot enable or price a logical product")
	native.products_loaded.emit("[]","network_error")
	await process_frame
	check(not store.is_available() and store.can_restore(),"Failed product loading still permits owned-purchase restoration")

	var timeout_store = create_service()
	var timeout_native = MockNative.new()
	timeout_store.initialization_timeout_seconds = 0.02
	timeout_store.initialize(timeout_native,settings())
	await create_timer(0.04).timeout
	check(not timeout_store.loading and not timeout_store.initialized and timeout_store.last_error=="initialization_timeout","Environment setup has a bounded timeout")
	var query_store = create_service()
	var query_native = MockNative.new()
	query_store.products_timeout_seconds = 0.02
	query_store.initialize(query_native,settings())
	query_native.env_ready.emit(true,"")
	await create_timer(0.05).timeout
	check(not query_store.loading and query_store.last_error=="products_timeout" and query_store.can_restore(),"Product query times out without disabling recovery")

	var fake = create_service()
	fake.simulate = true
	var fake_receipts:Array = []
	fake.delivery_requested.connect(func(value:Dictionary): fake_receipts.append(value))
	check(fake.is_available("coins_500") and fake.price("coins_500")=="$1.99","Explicit simulation preserves draft layout pricing")
	var fake_box:Array = []
	collect_purchase(fake,"coins_500",fake_box)
	await create_timer(0.04).timeout
	check(fake_receipts.size()==1 and fake_box.is_empty(),"Simulation also requires explicit delivery confirmation")
	fake.confirm_delivery(fake_receipts.pop_back(),true)
	var fake_result:Dictionary = await wait_result(fake_box,"Simulated purchase")
	check(fake_result.status=="delivered","Explicit simulation resolves through the same delivery contract")
	var fake_restore:Dictionary = await fake.restore()
	check(fake_restore.status=="empty","Simulation does not invent restored ownership")
	for service in services: service._disconnect_bridge()
	services.clear()
	# Let the short mock watchdogs finish before freeing their captured services.
	await create_timer(0.25).timeout
	print("STORE_SERVICE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
