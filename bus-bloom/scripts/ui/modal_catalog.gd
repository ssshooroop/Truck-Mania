extends RefCounted
## Every modal window of the game as data. Builders are pure: they read a small
## context Dictionary and return a spec for game_modal.gd. Action ids are the
## contract with the owner (main.gd or a test).
##
## Copy rules: address the player as "ты", short exclamatory title, button
## labels start with a verb, the price lives on the button, at most one primary
## (green) action and one ad (blue) action per window, exit is a quiet link.

const Style := preload("res://scripts/ui/modal_style.gd")
const STUCK_ART := preload("res://assets/artwork/menu/modals/open-extra-slot.png")
const WIN_ART := preload("res://assets/artwork/menu/Contented Construction Worker’s Ice Cream Break.png")
const BILLY_HAPPY := preload("res://assets/artwork/billy/billy-happy.png")
const BILLY_THINKING := preload("res://assets/artwork/billy/billy-thinking.png")
const BILLY_SURPRISED := preload("res://assets/artwork/billy/billy-surprised.png")
const CONE := preload("res://assets/artwork/cargo/traffic-cone.png")
const UNDO := preload("res://assets/artwork/menu/undo.png")
const GIFT := preload("res://assets/artwork/menu/gift.png")
const SHUFFLE := preload("res://assets/artwork/menu/shuffle.png")
const COINS_SMALL := preload("res://assets/artwork/menu/coins-stack-small.png")
const COINS_MEDIUM := preload("res://assets/artwork/menu/coins-stack-medium.png")
const COINS_BIG := preload("res://assets/artwork/menu/coins-stack-big.png")
const ITEM_ICONS := {
	"coins": COINS_BIG,
	"undo": UNDO,
	"extra_slot": CONE,
	"crane": GIFT,
	"shuffle": SHUFFLE,
	"swap": GIFT,
}

# ------------------------------------------------------------- tutorial

const TUTORIAL_STEPS := [
	{"title":"Привет, я Билли!","text":"Нажми на машину — она выедет по стрелке к складу.","cta":"Дальше","avatar":BILLY_HAPPY},
	{"title":"Цвет — это груз","text":"Машина берёт только свой материал. Следи за лентой сверху!","cta":"Дальше","avatar":BILLY_THINKING},
	{"title":"Мест всего три","text":"Не занимай места машинами, которым груз пока не нужен.","cta":"Начать работу","avatar":BILLY_HAPPY},
]

## Coach card at the bottom, optional spotlight (screen coordinates) on a truck.
static func tutorial(step:int,spotlight:Dictionary={}) -> Dictionary:
	var s: Dictionary = TUTORIAL_STEPS[clampi(step,0,TUTORIAL_STEPS.size()-1)]
	var spec := {
		"id":"tutorial","layout":"coach","avatar":s.avatar,"title":s.title,"back":"tutorial_skip",
		"blocks":[
			{"type":"text","text":s.text,"size":23},
			{"type":"steps","count":TUTORIAL_STEPS.size(),"index":step},
			{"type":"button","id":"tutorial_next","kind":"primary","label":s.cta,"pulse":true},
		],
	}
	if step<TUTORIAL_STEPS.size()-1: spec.blocks.append({"type":"link","id":"tutorial_skip","label":"Пропустить обучение"})
	if not spotlight.is_empty(): spec.spotlight = spotlight
	return spec

# ------------------------------------------------------------- dead end

## ctx: coins, slot_available, slot_price (0 = free), ad_ready, undo_price,
## undo_gifts, can_undo, shuffle_price, can_shuffle, crane_price, can_crane,
## rescue_left (bool)
static func stuck(ctx:Dictionary) -> Dictionary:
	var blocks: Array = [
		{"type":"art","texture":STUCK_ART,"height":210,"focus":Vector2(0.42,0.27)},
	]
	var help: bool = ctx.get("rescue_left",true)
	if ctx.get("slot_available",false) and help:
		var price := int(ctx.get("slot_price",100))
		blocks.append({"type":"text","text":"Все места у склада заняты.\nОткрой ещё одно — и продолжай!","size":21})
		blocks.append({"type":"button","id":"slot_coins","kind":"primary","label":"Открыть место","pulse":true,
			"price":{"free":true} if price==0 else {"coins":price}})
		if price>0: blocks.append({"type":"button","id":"slot_ad","kind":"ad","label":"Место за рекламу" if ctx.get("ad_ready",false) else "Ролик готовится…","enabled":ctx.get("ad_ready",false)})
	elif ctx.get("can_crane",false) and help:
		blocks.append({"type":"text","text":"Кран переставит нужную машину прямо к складу.","size":21})
		blocks.append({"type":"button","id":"crane","kind":"primary","label":"Вызвать кран","pulse":true,"price":{"coins":int(ctx.get("crane_price",150))}})
	else:
		blocks.append({"type":"text","text":"Помощь в этой попытке закончилась.\nОтмени ход или начни заново.","size":21})
	# A crane also needs a closed bay, so offer it alongside the slot purchase.
	if ctx.get("slot_available",false) and ctx.get("can_crane",false) and help:
		var price := int(ctx.get("crane_price",150))
		blocks.append({"type":"row","id":"crane","icon":ITEM_ICONS.crane,"title":"Вызвать кран",
			"subtitle":"Место и нужная машина","kind":"primary",
			"price":{} if price==0 else {"coins":price},"action_label":"Взять"})
	var gifts := int(ctx.get("undo_gifts",0))
	blocks.append({"type":"row","id":"undo","icon":UNDO,"title":"Отменить ход",
		"subtitle":("Бесплатно: ещё %d" % gifts) if gifts>0 else "Вернуть последнюю машину",
		"kind":"primary","price":{} if gifts>0 else {"coins":int(ctx.get("undo_price",20))},"action_label":"Взять",
		"enabled":ctx.get("can_undo",true)})
	if ctx.get("can_shuffle",false) and help:
		blocks.append({"type":"row","id":"shuffle","icon":SHUFFLE,"title":"Перемешать груз",
			"subtitle":"Новый порядок на ленте","kind":"primary","price":{"coins":int(ctx.get("shuffle_price",30))}})
	blocks.append({"type":"link","id":"retry","label":"Начать уровень заново"})
	return {"id":"stuck","title":"Парковка заполнена!","balance":int(ctx.get("coins",0)),"back":"menu","blocks":blocks}

# ------------------------------------------------------------- single offer

## One item, coins or an ad. item: "extra_slot" | "crane" | "shuffle" | "undo".
static func offer(item:String,price:int,coins:int,ad_ready:bool) -> Dictionary:
	var copy: Dictionary = {
		"extra_slot":{"title":"Убрать конус?","text":"Четвёртое место у склада\nдо конца этой попытки.","cta":"Убрать"},
		"crane":{"title":"Вызвать кран?","text":"Кран поставит нужную машину\nна свободное место.","cta":"Вызвать"},
		"shuffle":{"title":"Перемешать груз?","text":"Материалы на ленте\nвстанут в новом порядке.","cta":"Перемешать"},
		"undo":{"title":"Отменить ход?","text":"Последняя машина\nвернётся на парковку.","cta":"Отменить"},
	}.get(item,{"title":"Помощь","text":"","cta":"Взять"})
	var blocks: Array = [
		{"type":"hero","texture":ITEM_ICONS.get(item,GIFT),"size":150},
		{"type":"text","text":copy.text,"size":22},
		{"type":"button","id":"buy","kind":"primary","label":copy.cta,"pulse":true,"price":{"free":true} if price==0 else {"coins":price}},
	]
	if price>0: blocks.append({"type":"button","id":"watch_ad","kind":"ad","label":"Бесплатно с рекламой" if ad_ready else "Ролик готовится…","enabled":ad_ready})
	blocks.append({"type":"link","id":"close","label":"Не сейчас"})
	return {"id":"offer_"+item,"title":copy.title,"close":true,"back":"close","balance":coins,"blocks":blocks}

# ------------------------------------------------------------- not enough coins

## pack: {"coins":500,"price":"$1.99"} — the smallest store pack that covers
## the gap — or {} when no store is configured.
static func shortfall(need:int,coins:int,ad_coins:int,ad_ready:bool,pack:Dictionary={}) -> Dictionary:
	var missing := maxi(0,need-coins)
	var blocks: Array = [
		{"type":"hero","texture":BILLY_SURPRISED,"size":150,"rays":false},
		{"type":"text","text":"Нужно ещё %d %s." % [missing,coin_word(missing)],"size":24},
		{"type":"button","id":"watch_ad","kind":"ad","label":("+%d за рекламу" % ad_coins) if ad_ready else "Ролик готовится…","pulse":true,"enabled":ad_ready},
	]
	if not pack.is_empty():
		blocks.append({"type":"button","id":"buy_pack","kind":"primary","label":"%d монет" % int(pack.coins),"icon":COINS_MEDIUM,"price":{"money":pack.price}})
		blocks.append({"type":"link","id":"shop","label":"Все наборы в магазине"})
	else: blocks.append({"type":"link","id":"close","label":"Не сейчас"})
	return {"id":"shortfall","title":"Не хватает монет","close":true,"back":"close","balance":coins,"blocks":blocks}

# ------------------------------------------------------------- rewarded ad

## state: "offer" | "loading" | "failed" | "done"
static func ad_reward(state:String,amount:int,coins:int) -> Dictionary:
	var blocks: Array = []
	match state:
		"done":
			blocks = [
				{"type":"reward","amount":amount},
				{"type":"text","text":"Монеты уже в копилке!","size":22},
				{"type":"button","id":"close","kind":"primary","label":"Отлично!","pulse":true},
			]
			return {"id":"ad_reward","title":"Награда получена!","balance":coins,"back":"close","blocks":blocks}
		"loading":
			blocks = [
				{"type":"hero","texture":Style.AD,"size":130},
				{"type":"status","text":"Загружаем ролик…","spinner":true},
				{"type":"link","id":"close","label":"Отмена"},
			]
		"failed":
			blocks = [
				{"type":"hero","texture":BILLY_THINKING,"size":140,"rays":false},
				{"type":"text","text":"Ролик не загрузился.\nПроверь интернет и попробуй ещё раз.","size":21},
				{"type":"button","id":"watch_ad","kind":"ad","label":"Попробовать ещё","pulse":false},
				{"type":"link","id":"close","label":"Закрыть"},
			]
		_:
			blocks = [
				{"type":"hero","texture":COINS_MEDIUM,"size":140},
				{"type":"text","text":"Посмотри короткий ролик\nи получи %d %s." % [amount,coin_word(amount)],"size":22},
				{"type":"button","id":"watch_ad","kind":"ad","label":"Смотреть","pulse":true,"price":{"coins":amount}},
				{"type":"link","id":"close","label":"Не сейчас"},
			]
	return {"id":"ad_reward","title":"Бесплатные монеты","close":state!="loading","back":"close","balance":coins,"blocks":blocks}

# ------------------------------------------------------------- level complete

## ctx: reward, before (balance before the reward), coins, last (bool),
## can_double (bool), details (runtime_economy completion() result).
static func win(ctx:Dictionary) -> Dictionary:
	var reward := int(ctx.get("reward",0))
	var blocks: Array = [{"type":"art","texture":WIN_ART,"height":250,"focus":Vector2(0.5,0.30)}]
	if reward>0:
		blocks.append({"type":"reward","amount":reward})
		var parts := reward_parts(ctx.get("details",{}))
		if parts!="": blocks.append({"type":"text","text":parts,"size":18,"color":Style.MUTED})
		if ctx.get("can_double",false):
			blocks.append({"type":"button","id":"double","kind":"ad","label":"Удвоить награду","price":{"coins":reward}})
	else: blocks.append({"type":"text","text":"Награда за этот уровень\nуже получена.","size":21})
	blocks.append({"type":"button","id":"next","kind":"primary","pulse":true,
		"label":"Карта уровней" if ctx.get("last",false) else "Следующий уровень"})
	blocks.append({"type":"link","id":"replay","label":"Сыграть ещё раз"})
	return {"id":"win","title":"Груз отправлен!","balance":int(ctx.get("coins",0)),
		"balance_from":int(ctx.get("before",ctx.get("coins",0))),"fly":reward>0,"back":"map","blocks":blocks}

## "Уровень +20 · Серия +10" when the reward has more than one source.
static func reward_parts(details:Dictionary) -> String:
	var parts: Array = []
	for key in ["base","streak","chest","achievements"]:
		var n := int(details.get(key,0))
		if n>0: parts.append("%s +%d" % [{"base":"Уровень","streak":"Серия","chest":"Сундук","achievements":"Достижения"}[key],n])
	return " · ".join(parts) if parts.size()>1 else ""

# ------------------------------------------------------------- seasonal

## event: an entry returned by active_event(); store: store_service.gd for the
## bundle's contents and price. `frozen_now` (unix seconds) pins the countdown
## for screenshots; 0 keeps it live.
static func seasonal(event:Dictionary,store,frozen_now:int=0) -> Dictionary:
	var product: Dictionary = store.product(event.get("product",""))
	var blocks: Array = [
		{"type":"art","texture":load(event.art),"height":220,"focus":Vector2(event.get("focus_x",0.5),event.get("focus_y",0.4))},
		{"type":"timer","ends_at":int(event.ends_at),"label":"До конца"},
		{"type":"text","text":event.get("text",""),"size":21},
		{"type":"bundle","items":items_for(product.get("contents",{}))},
		{"type":"button","id":"buy_bundle","kind":"primary","label":event.get("cta","Забрать набор"),"pulse":true,
			"price":{"money":store.price(product.id)}},
		{"type":"link","id":"close","label":"Позже"},
	]
	if product.has("old_usd"): blocks[4].note = "Обычная цена %s" % store.old_price(product.id)
	if frozen_now>0: blocks[1].now = frozen_now
	var spec := {"id":"seasonal_"+str(event.get("id","")),"title":event.get("title","Сезонная акция"),"close":true,"back":"close","blocks":blocks}
	var off := discount(product)
	if off!="": spec.ribbon = off
	return spec

## Active event for a unix time, or {} (dates are inclusive UTC days).
static func active_event(events:Array,now:int) -> Dictionary:
	for e: Dictionary in events:
		var starts := Time.get_unix_time_from_datetime_string(str(e.get("starts","")))
		var ends := Time.get_unix_time_from_datetime_string(str(e.get("ends","")))+86400
		if now>=starts and now<ends:
			var copy := e.duplicate(true)
			copy.ends_at = ends
			return copy
	return {}

static func load_events() -> Array:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://config/seasonal_events.json"))
	return data.get("events",[]) if data is Dictionary else []

# ------------------------------------------------------------- shop

## ctx: coins, store (store_service.gd), owned (Array of once-only product ids),
## event (active seasonal event or {}), ad_ready, ad_coins, frozen_now.
static func shop(ctx:Dictionary) -> Dictionary:
	var store = ctx.store
	var owned: Array = ctx.get("owned",[])
	var event: Dictionary = ctx.get("event",{})
	var now := int(ctx.get("frozen_now",0))
	if now<=0: now = int(Time.get_unix_time_from_system())
	var blocks: Array = []
	var featured: Array = []
	if not event.is_empty() and event.get("product","") not in owned: featured.append(event.product)
	if "starter" not in owned and store.products.has("starter"): featured.append("starter")
	for id: String in featured:
		var p: Dictionary = store.product(id)
		var deal := {"type":"deal","id":"buy:"+id,"title":p.get("title",""),"items":items_for(p.contents),"price":store.price(id)}
		if id==event.get("product",""):
			deal.art = load(event.art)
			deal.focus = Vector2(event.get("focus_x",0.5),event.get("focus_y",0.4))
			deal.subtitle = "%s · ещё %s" % [event.title,_days(int(event.ends_at)-now)]
		else:
			deal.icon = GIFT
			deal.subtitle = p.get("subtitle","")
		if p.has("old_usd"): deal.old_price = store.old_price(id)
		var off := discount(p)
		if off!="": deal.tag = off
		blocks.append(deal)
	blocks.append({"type":"label","text":"Монеты"})
	var ad_ready: bool = ctx.get("ad_ready",false)
	var tiles: Array = [{"id":"free_coins","icon":Style.COIN,"amount":str(int(ctx.get("ad_coins",25))),"kind":"ad",
		"price":"Бесплатно" if ad_ready else "Скоро","enabled":ad_ready}]
	for id: String in store.coin_packs():
		var p: Dictionary = store.product(id)
		var tile := {"id":"buy:"+id,"icon":load("res://assets/artwork/menu/"+p.icon),"amount":_thousands(int(p.contents.coins)),"price":store.price(id)}
		if store.bonus(id)!="": tile.bonus = store.bonus(id)
		if p.has("tag"): tile.tag = p.tag
		tiles.append(tile)
	blocks.append({"type":"packs","columns":3,"tiles":tiles})
	blocks.append({"type":"link","id":"restore","label":"Восстановить покупки"})
	return {"id":"shop","title":"Магазин","close":true,"back":"close","balance":int(ctx.get("coins",0)),"blocks":blocks}

## After a successful purchase: what arrived.
static func received(contents:Dictionary,coins:int) -> Dictionary:
	return {"id":"received","title":"Готово!","balance":coins,"back":"close","blocks":[
		{"type":"hero","texture":BILLY_HAPPY,"size":150},
		{"type":"text","text":"Всё уже на складе. За работу!","size":22},
		{"type":"bundle","items":items_for(contents)},
		{"type":"button","id":"close","kind":"primary","label":"Отлично!","pulse":true},
	]}

static func items_for(contents:Dictionary) -> Array:
	var items: Array = []
	for key: String in contents:
		var n := int(contents[key])
		items.append({"texture":ITEM_ICONS.get(key,GIFT),"count":_thousands(n) if key=="coins" else "×%d" % n})
	return items

## "−60%" from a product's draft old price, or "".
static func discount(p:Dictionary) -> String:
	if not p.has("old_usd") or float(p.old_usd)<=0.0: return ""
	return "−%d%%" % roundi((1.0-float(p.usd)/float(p.old_usd))*100.0)

static func _thousands(n:int) -> String:
	var s := str(n)
	return s if n<10000 else s.substr(0,s.length()-3)+" "+s.substr(s.length()-3)

static func _days(seconds:int) -> String:
	seconds = maxi(0,seconds)
	if seconds>=86400: return "%d д" % (seconds/86400)
	return "%d ч" % maxi(1,seconds/3600)

static func coin_word(n:int) -> String:
	var m10 := n%10
	var m100 := n%100
	if m10==1 and m100!=11: return "монета"
	if m10>=2 and m10<=4 and (m100<12 or m100>14): return "монеты"
	return "монет"
