extends RefCounted
## Real-money store seam over config/store_catalog.json. No store SDK is
## connected yet: `is_available()` is false and nothing is granted. Prices shown
## until then are the catalog's draft USD references. `simulate` (command line
## `--fake-store`) completes purchases after 1 s so the flows can be tested.
## To connect an SDK: fill `localized` with the store's price strings and make
## purchase() resolve true only after the store confirms the transaction.

var products: Dictionary = {}
var order: Array = []
var localized: Dictionary = {}
var simulate := false
var buying := false

func _init() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://config/store_catalog.json"))
	for p: Dictionary in data.products:
		products[p.id] = p
		order.append(p.id)

func is_available() -> bool:
	return simulate and not buying

func product(id:String) -> Dictionary:
	return products.get(id,{})

func coin_packs() -> Array:
	return order.filter(func(id): return products[id].kind=="coins")

func price(id:String) -> String:
	if localized.has(id): return localized[id]
	return _usd(float(product(id).get("usd",0.0)))

func old_price(id:String) -> String:
	var p := product(id)
	return _usd(float(p.old_usd)) if p.has("old_usd") else ""

## Extra coins per dollar compared with the smallest pack, e.g. "+30%".
func bonus(id:String) -> String:
	var packs := coin_packs()
	if packs.is_empty() or id==packs[0]: return ""
	var base: Dictionary = products[packs[0]]
	var p := product(id)
	var gain := (float(p.contents.coins)/float(p.usd))/(float(base.contents.coins)/float(base.usd))-1.0
	return "+%d%%" % roundi(gain*100.0) if gain>=0.05 else ""

## Smallest coin pack that covers `missing` coins (or the largest one).
func pack_for(missing:int) -> String:
	var packs := coin_packs()
	for id in packs:
		if int(products[id].contents.coins)>=missing: return id
	return packs.back() if not packs.is_empty() else ""

func purchase(id:String) -> bool:
	if not is_available() or not products.has(id): return false
	buying = true
	await Engine.get_main_loop().create_timer(1.0).timeout
	buying = false
	return true

static func _usd(value:float) -> String:
	return "$%.2f" % value
