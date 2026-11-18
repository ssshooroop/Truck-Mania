extends SceneTree
const Catalog = preload("res://scripts/ui/modal_catalog.gd")
const Modal = preload("res://scripts/ui/game_modal.gd")
const Loc = preload("res://scripts/localization.gd")

class StoreView extends RefCounted:
	var simulate := false
	var initialized := false
	var buying := false
	var products: Dictionary = {}
	var order: Array = []
	var localized: Dictionary = {}
	func _init() -> void:
		for item in JSON.parse_string(FileAccess.get_file_as_string("res://config/store_catalog.json")).products:
			products[item.id] = item
			order.append(item.id)
	func product(id: String) -> Dictionary: return products.get(id,{})
	func coin_packs() -> Array: return order.filter(func(id): return products[id].kind=="coins")
	func is_available(id: String="") -> bool:
		return not buying and (simulate or (initialized and (not localized.is_empty() if id.is_empty() else localized.has(id))))
	func can_restore() -> bool: return not buying and (simulate or initialized)
	func price(id: String) -> String:
		return "$%.2f" % products[id].usd if simulate else str(localized.get(id,"Недоступно"))
	func old_price(id: String) -> String:
		# Even a stale draft string must not leak into a real store offer.
		return "$%.2f" % products[id].old_usd if products[id].has("old_usd") else ""
	func bonus(_id: String) -> String: return "+30%" if simulate else ""

var failures := 0
var checks := 0
var actions: Array = []

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func block(spec: Dictionary,id: String) -> Dictionary:
	for b in spec.blocks:
		if b.get("id","")==id: return b
		if b.type=="packs":
			for t in b.tiles:
				if t.id==id: return t
	return {}

func modal_for(spec: Dictionary,viewport: Vector2) -> Control:
	var modal = Modal.new(spec)
	root.add_child(modal)
	modal.set_anchors_preset(Control.PRESET_TOP_LEFT)
	modal.size = viewport
	modal.age = 1.0
	modal._layout()
	modal.action.connect(func(id): actions.append(id))
	return modal

func _initialize() -> void: run.call_deferred()

func run() -> void:
	Loc.initialize()
	var store = StoreView.new()
	for viewport in [Vector2(540,720),Vector2(540,1171)]:
		var unavailable = Catalog.shop({"store":store,"owned":[],"ad_ready":true,"coins":50})
		for id in store.order:
			var item = block(unavailable,"buy:"+id)
			if item.is_empty(): continue # inactive seasonal bundles stay out of the shop
			check(not item.enabled,"Unavailable product is disabled: "+id)
			check(item.price=="Недоступно","Real UI never falls back to catalog USD")
			check(not item.has("old_price") and not item.has("tag") and not item.has("bonus"),"No draft discount/promotion in real store")
		check(block(unavailable,"free_coins").enabled,"Rewarded ads stay independent of IAP availability")
		check(not block(unavailable,"restore").enabled,"Restore disabled before store initialization")
		var modal = modal_for(unavailable,viewport)
		actions.clear()
		check(not modal.tap("buy:coins_500") and not modal.tap("buy:starter") and not modal.tap("restore"),"Disabled controls cannot emit purchase actions")
		check(actions.is_empty(),"No purchase or restore event while unavailable")
		check(modal.tap("free_coins") and actions==["free_coins"],"Free ad tile remains actionable")
		modal.free()

		store.initialized = true
		store.localized = {"coins_500":"₺79,99"}
		var ready = Catalog.shop({"store":store,"owned":[],"ad_ready":false})
		check(block(ready,"buy:coins_500").price=="₺79,99","Store-localized currency string is shown verbatim")
		check(block(ready,"buy:coins_500").enabled and not block(ready,"buy:coins_1200").enabled,"Availability is per product")
		check(block(ready,"restore").enabled,"Restore works even with an incomplete product response")
		modal = modal_for(ready,viewport)
		actions.clear()
		check(modal.tap("buy:coins_500") and not modal.tap("buy:coins_1200"),"Only fetched product is actionable")
		check(actions==["buy:coins_500"],"Action retains logical product ID")
		modal.free()

		store.buying = true
		var busy = Catalog.shop({"store":store,"owned":[],"ad_ready":true})
		check(not block(busy,"buy:coins_500").enabled and not block(busy,"restore").enabled,"Busy store prevents a second purchase/restore")
		check(block(busy,"free_coins").enabled,"IAP busy does not change ad readiness")
		store.buying = false
		store.initialized = false
		store.localized.clear()

	var winter_time := int(Time.get_unix_time_from_datetime_string("2026-12-25T12:00:00"))
	var event = Catalog.active_event(Catalog.load_events(),winter_time)
	var seasonal = Catalog.seasonal(event,store,winter_time)
	check(not block(seasonal,"buy_bundle").enabled,"Seasonal purchase waits for its store product")
	check(block(seasonal,"buy_bundle").product_id==event.product,"Seasonal button exposes product ID for live refresh")
	check(not seasonal.has("ribbon") and not block(seasonal,"buy_bundle").has("note"),"Seasonal offer hides draft discount and old price")
	var shortfall = Catalog.shortfall(500,10,25,true,{"product_id":"coins_500","coins":500,"price":"Недоступно","enabled":false})
	check(not block(shortfall,"buy_pack").enabled and block(shortfall,"buy_pack").product_id=="coins_500","Shortfall offer uses per-product availability")
	check(block(shortfall,"watch_ad").enabled,"Shortfall ad remains available independently")
	shortfall = Catalog.shortfall(500,10,25,true,{"coins":500,"price":"₺79,99","enabled":true})
	check(block(shortfall,"buy_pack").enabled,"Available shortfall offer is enabled")

	store.simulate = true
	var preview = Catalog.shop({"store":store,"owned":[]})
	check(block(preview,"buy:starter").enabled and block(preview,"buy:starter").has("old_price"),"Explicit fake-store preview retains draft layout")
	check(block(preview,"buy:coins_2600").get("bonus","")=="+30%","Explicit fake-store preview retains bonus labels")
	preview = Catalog.shop({"store":store,"owned":["starter"]})
	check(block(preview,"buy:starter").is_empty(),"Owned one-time product stays hidden")

	for language in Loc.SUPPORTED:
		Loc.set_locale(language)
		for id in Loc.messages:
			if not str(id).begins_with("store.status."): continue
			var item: Dictionary = Loc.messages[id]
			check(language=="ru" or item.translations.has(language),"Store status translated: "+language+" / "+id)
			check(not Loc.text(item.source).is_empty(),"Store status resolves: "+language+" / "+id)
	Loc.set_locale("ru")
	print("Store UI: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
