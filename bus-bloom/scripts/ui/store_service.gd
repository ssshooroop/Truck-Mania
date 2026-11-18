extends RefCounted
## Huawei verifies payment in TruckManiaIap. The game must persist each delivery
## and its transaction ledger before calling confirm_delivery(receipt, true).
## This service never grants goods. Only explicit --fake-store enables simulation.
signal availability_changed
signal delivery_requested(receipt:Dictionary)
signal operation_completed(request_id:int)

var products:Dictionary = {}
var order:Array = []
var localized:Dictionary = {}
var simulate := false
var buying := false
var initialized := false
var loading := false
var state := "unavailable"
var last_error := ""
var bridge:Object
var initialization_timeout_seconds := 25.0
var products_timeout_seconds := 25.0
var operation_timeout_seconds := 180.0
var simulation_delay_seconds := 1.0
var operation_kind:String:
	get: return _active_kind
var _registered:Dictionary = {}
var _priced:Dictionary = {}
var _pending_receipts:Dictionary = {}
var _receipt_versions:Dictionary = {}
var _receipt_sequence := 0
var _results:Dictionary = {}
var _sequence := 0
var _active_request := 0
var _active_kind := ""
var _active_product := ""
var _active_pending:Dictionary = {}
var _active_confirmed:Dictionary = {}
var _active_delivered := 0
var _active_delivery_failed := false
var _native_finished := false
var _query_serial := 0
var _init_serial := 0

func _init() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://config/store_catalog.json"))
	if not data is Dictionary or not data.get("products") is Array: return
	for entry in data.products:
		if not entry is Dictionary or not entry.get("id") is String: continue
		var id:String = entry.id
		if id.is_empty() or products.has(id): continue
		products[id] = entry
		order.append(id)

## Overrides are for mock-native tests; normal game startup passes no arguments.
func initialize(native_override:Object=null,settings_override:Variant=null) -> bool:
	if buying or loading or initialized: return false
	if simulate:
		state = "ready"
		last_error = ""
		availability_changed.emit()
		return true
	if native_override==null and not OS.has_feature("huawei_appgallery"):
		return _initialization_failed("unsupported_store")
	var settings:Variant = settings_override
	if settings==null:
		if not FileAccess.file_exists("res://config/huawei_iap.json"):
			return _initialization_failed("missing_configuration")
		settings = JSON.parse_string(FileAccess.get_file_as_string("res://config/huawei_iap.json"))
	if not settings is Dictionary or not settings.get("app_id") is String \
			or not settings.get("public_key") is String or not settings.get("product_ids") is Dictionary:
		return _initialization_failed("missing_configuration")
	if str(settings.app_id).strip_edges().is_empty() or str(settings.public_key).strip_edges().is_empty():
		return _initialization_failed("missing_configuration")
	_registered.clear()
	var catalog:Array = []
	var store_ids:Dictionary = {}
	for id:String in order:
		var sku:Variant = settings.product_ids.get(id,"")
		if not sku is String or sku.strip_edges().is_empty(): continue
		if store_ids.has(sku): return _initialization_failed("duplicate_product_id")
		store_ids[sku] = true
		_registered[id] = sku
		catalog.append({"id":id,"product_id":sku,"type":_product_type(id)})
	if catalog.is_empty(): return _initialization_failed("missing_product_ids")
	if native_override==null and not Engine.has_singleton("TruckManiaIap"):
		return _initialization_failed("sdk_unavailable")
	var native:Object = native_override if native_override!=null else Engine.get_singleton("TruckManiaIap")
	for method:String in ["initialize","query_products","purchase","restore","confirm_delivery"]:
		if not native.has_method(method): return _initialization_failed("sdk_incompatible")
	for event:String in ["env_ready","products_loaded","purchase_verified","operation_finished","consumed"]:
		if not native.has_signal(event): return _initialization_failed("sdk_incompatible")
	_disconnect_bridge()
	bridge = native
	bridge.connect("env_ready",_on_env_ready,CONNECT_DEFERRED)
	bridge.connect("products_loaded",_on_products_loaded,CONNECT_DEFERRED)
	bridge.connect("purchase_verified",_on_purchase_verified,CONNECT_DEFERRED)
	bridge.connect("operation_finished",_on_operation_finished,CONNECT_DEFERRED)
	bridge.connect("consumed",_on_consumed,CONNECT_DEFERRED)
	state = "initializing"
	loading = true
	last_error = ""
	_init_serial += 1
	_initialization_timeout(_init_serial)
	availability_changed.emit()
	bridge.initialize(str(settings.app_id),str(settings.public_key),JSON.stringify(catalog))
	return true

func _disconnect_bridge() -> void:
	if not is_instance_valid(bridge): return
	var callbacks := {"env_ready":_on_env_ready,"products_loaded":_on_products_loaded,
		"purchase_verified":_on_purchase_verified,"operation_finished":_on_operation_finished,"consumed":_on_consumed}
	for event:String in callbacks:
		if bridge.is_connected(event,callbacks[event]): bridge.disconnect(event,callbacks[event])

func _initialization_failed(reason:String) -> bool:
	initialized = false
	loading = false
	state = "unavailable"
	last_error = reason
	localized.clear()
	_priced.clear()
	availability_changed.emit()
	return false

func _initialization_timeout(ticket:int) -> void:
	await Engine.get_main_loop().create_timer(maxf(0.01,initialization_timeout_seconds)).timeout
	if ticket==_init_serial and state=="initializing": _initialization_failed("initialization_timeout")

func _on_env_ready(ok:bool,error:String) -> void:
	loading = false
	if not ok:
		_initialization_failed(error if not error.is_empty() else "environment_unavailable")
		return
	initialized = true
	last_error = ""
	refresh_products()

func refresh_products() -> bool:
	if simulate or not initialized or not is_instance_valid(bridge) or loading: return false
	loading = true
	state = "loading_products"
	_query_serial += 1
	_products_timeout(_query_serial)
	availability_changed.emit()
	bridge.query_products()
	return true

func _products_timeout(ticket:int) -> void:
	await Engine.get_main_loop().create_timer(maxf(0.01,products_timeout_seconds)).timeout
	if ticket!=_query_serial or state!="loading_products": return
	loading = false
	state = "error"
	last_error = "products_timeout"
	localized.clear()
	_priced.clear()
	availability_changed.emit()

func _on_products_loaded(payload:String,error:String) -> void:
	if not initialized: return
	loading = false
	localized.clear()
	_priced.clear()
	var entries:Variant = JSON.parse_string(payload)
	if not error.is_empty() or not entries is Array:
		state = "error"
		last_error = error if not error.is_empty() else "invalid_products"
		availability_changed.emit()
		return
	var seen:Dictionary = {}
	for entry in entries:
		if not entry is Dictionary or not entry.get("id") is String: continue
		var id:String = entry.id
		if not _registered.has(id): continue
		if seen.has(id):
			localized.erase(id)
			_priced.erase(id)
			continue
		seen[id] = true
		if entry.get("product_id")!=_registered[id] or not _integer(entry.get("type")) \
				or int(entry.type)!=_product_type(id) or not entry.get("price") is String: continue
		var text:String = entry.price.strip_edges()
		if text.is_empty() or text.length()>128: continue
		localized[id] = text
		_priced[id] = entry.duplicate(true)
	state = "ready" if not _priced.is_empty() else "unavailable"
	last_error = "" if not _priced.is_empty() else "products_unavailable"
	availability_changed.emit()

func is_available(id:String="") -> bool:
	if buying: return false
	if simulate: return not products.is_empty() if id.is_empty() else products.has(id)
	if not initialized or not is_instance_valid(bridge): return false
	return not _priced.is_empty() if id.is_empty() else _registered.has(id) and _priced.has(id)

func can_restore() -> bool:
	return not buying and (simulate or initialized and is_instance_valid(bridge))

func product(id:String) -> Dictionary:
	return products.get(id,{})

func coin_packs() -> Array:
	return order.filter(func(id): return products[id].get("kind")=="coins")

func price(id:String) -> String:
	if simulate: return str(localized[id]) if localized.has(id) else _usd(float(product(id).get("usd",0.0)))
	if _registered.has(id) and _priced.has(id): return str(localized[id])
	return "..." if loading and products.has(id) else "Недоступно"

func old_price(id:String) -> String:
	var p := product(id)
	return _usd(float(p.old_usd)) if simulate and p.has("old_usd") else ""

func bonus(id:String) -> String:
	if not simulate: return ""
	var packs := coin_packs()
	if packs.is_empty() or id==packs[0] or not products.has(id): return ""
	var base:Dictionary = products[packs[0]]
	var p:Dictionary = products[id]
	if float(p.get("usd",0.0))<=0.0 or float(base.get("usd",0.0))<=0.0: return ""
	var gain := (float(p.contents.coins)/float(p.usd))/(float(base.contents.coins)/float(base.usd))-1.0
	return "+%d%%" % roundi(gain*100.0) if gain>=0.05 else ""

func pack_for(missing:int) -> String:
	var packs := coin_packs()
	for id in packs:
		if int(products[id].contents.coins)>=missing: return id
	return packs.back() if not packs.is_empty() else ""

func purchase(id:String) -> Dictionary:
	if buying: return _result(0,"busy","operation_in_progress",id)
	if not products.has(id) or not is_available(id): return _result(0,"unavailable","product_unavailable",id)
	var ticket := _begin_operation("purchase",id)
	if simulate: _simulate_purchase(ticket,id)
	else: bridge.purchase(id,ticket)
	return await _await_result(ticket)

func restore() -> Dictionary:
	if buying: return _result(0,"busy","operation_in_progress")
	if not can_restore(): return _result(0,"unavailable","store_unavailable")
	var ticket := _begin_operation("restore")
	if simulate: _simulate_restore(ticket)
	else: bridge.restore(ticket)
	return await _await_result(ticket)

func _begin_operation(kind:String,id:String="") -> int:
	_sequence += 1
	_active_request = _sequence
	_active_kind = kind
	_active_product = id
	_active_pending.clear()
	_active_confirmed.clear()
	_active_delivered = 0
	_active_delivery_failed = false
	_native_finished = false
	buying = true
	last_error = ""
	_operation_timeout(_active_request)
	availability_changed.emit()
	return _active_request

func _await_result(ticket:int) -> Dictionary:
	while not _results.has(ticket): await operation_completed
	var result:Dictionary = _results[ticket]
	_results.erase(ticket)
	return result

func _operation_timeout(ticket:int) -> void:
	await Engine.get_main_loop().create_timer(maxf(0.01,operation_timeout_seconds)).timeout
	if _active_request!=ticket: return
	_finish_operation("pending" if _active_kind=="purchase" else "failed","operation_timeout")

func _on_purchase_verified(payload:String) -> void:
	var value:Variant = JSON.parse_string(payload)
	if not _valid_receipt(value):
		last_error = "invalid_receipt"
		availability_changed.emit()
		return
	var receipt:Dictionary = {"id":value.id,"token":value.token,"order_id":value.order_id,
		"type":int(value.type),"source":value.source,"request_id":int(value.request_id)}
	var token:String = receipt.token
	if _pending_receipts.has(token): return
	_pending_receipts[token] = receipt
	_receipt_sequence += 1
	_receipt_versions[token] = _receipt_sequence
	_delivery_timeout(token,_receipt_sequence)
	if int(receipt.request_id)==_active_request and _active_request!=0:
		_active_pending[token] = true
	delivery_requested.emit(receipt.duplicate(true))

func _delivery_timeout(token:String,generation:int) -> void:
	await Engine.get_main_loop().create_timer(maxf(0.01,operation_timeout_seconds)).timeout
	if _receipt_versions.get(token)!=generation or not _pending_receipts.has(token): return
	# Do not suppress future owned-purchase recovery forever if a delivery
	# callback failed to confirm. An unconfirmed token is never consumed.
	confirm_delivery(_pending_receipts[token],false)

func _valid_receipt(value:Variant) -> bool:
	if not value is Dictionary: return false
	for key:String in ["id","token","order_id","source"]:
		if not value.get(key) is String or value[key].strip_edges().is_empty(): return false
	if not products.has(value.id) or (not simulate and not _registered.has(value.id)): return false
	if value.source not in ["purchase","restore","recovery"]: return false
	if not _integer(value.get("type")) or int(value.type)!=_product_type(value.id): return false
	if not _integer(value.get("request_id")) or int(value.request_id)<0: return false
	if value.token.length()>65536 or value.order_id.length()>1024: return false
	if int(value.request_id)==_active_request and _active_kind=="purchase" and value.id!=_active_product: return false
	return true

## success means the grant AND transaction ledger are durably saved by main.
## A false confirmation keeps Huawei ownership unconsumed for later recovery.
func confirm_delivery(receipt:Dictionary,success:bool) -> void:
	var token:String = str(receipt.get("token",""))
	if not _pending_receipts.has(token): return
	var trusted:Dictionary = _pending_receipts[token]
	for key:String in ["id","token","order_id","type","request_id","source"]:
		if receipt.get(key)!=trusted.get(key): return
	_pending_receipts.erase(token)
	_receipt_versions.erase(token)
	var current := int(trusted.request_id)==_active_request and _active_request!=0
	if current:
		_active_pending.erase(token)
		if success and not _active_confirmed.has(trusted.order_id):
			_active_confirmed[trusted.order_id] = true
			_active_delivered += 1
		elif not success: _active_delivery_failed = true
	if success and not simulate and is_instance_valid(bridge): bridge.confirm_delivery(token)
	if not success: last_error = "delivery_failed"
	if current:
		if _active_kind=="purchase":
			_finish_operation("delivered" if success else "failed","" if success else "delivery_failed")
		elif _native_finished and _active_pending.is_empty(): _finish_restore()

func _on_operation_finished(ticket:int,status:String,error:String) -> void:
	if ticket!=_active_request or ticket==0: return
	if status in ["success","verified","restored"]:
		_native_finished = true
		if _active_kind=="restore" and _active_pending.is_empty(): _finish_restore()
		elif _active_kind=="purchase" and _active_delivered>0: _finish_operation("delivered")
		# A native success without a verified, persisted receipt is never a grant.
		return
	var safe_status := status if status in ["cancelled","pending","failed","unavailable","busy"] else "failed"
	_finish_operation(safe_status,error if not error.is_empty() else status)

func _finish_restore() -> void:
	if _active_delivery_failed: _finish_operation("failed","delivery_failed")
	else: _finish_operation("restored" if _active_delivered>0 else "empty")

func _on_consumed(_token:String,ok:bool,error:String) -> void:
	if ok: return
	# Saved deliveries remain valid; recovery may retry consumption later.
	last_error = error if not error.is_empty() else "consumption_pending"
	availability_changed.emit()

func _finish_operation(status:String,error:String="") -> void:
	var ticket := _active_request
	if ticket==0: return
	_results[ticket] = _result(ticket,status,error,_active_product)
	_results[ticket]["delivered_count"] = _active_delivered
	_active_request = 0
	_active_kind = ""
	_active_product = ""
	_active_pending.clear()
	buying = false
	last_error = error
	operation_completed.emit(ticket)
	availability_changed.emit()

func _simulate_purchase(ticket:int,id:String) -> void:
	await Engine.get_main_loop().create_timer(maxf(0.01,simulation_delay_seconds)).timeout
	if ticket!=_active_request: return
	var token := "fake:%s:%s:%s" % [id,str(Time.get_ticks_usec()),str(ticket)]
	_on_purchase_verified(JSON.stringify({"id":id,"token":token,"order_id":token,
		"type":_product_type(id),"source":"purchase","request_id":ticket}))
	_on_operation_finished(ticket,"verified","")

func _simulate_restore(ticket:int) -> void:
	await Engine.get_main_loop().create_timer(maxf(0.01,simulation_delay_seconds)).timeout
	_on_operation_finished(ticket,"restored","")

func _product_type(id:String) -> int:
	return 1 if bool(product(id).get("once",false)) else 0

static func _integer(value:Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)==float(int(value))

static func _result(ticket:int,status:String,error:String="",id:String="") -> Dictionary:
	return {"request_id":ticket,"status":status,"error":error,"id":id}

static func _usd(value:float) -> String:
	return "$%.2f" % value
