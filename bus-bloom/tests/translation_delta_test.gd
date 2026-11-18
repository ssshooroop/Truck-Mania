extends SceneTree
const Loc = preload("res://scripts/localization.gd")
const Catalog = preload("res://scripts/ui/modal_catalog.gd")
const Text = preload("res://scripts/ui/localized_text.gd")
func _initialize():
	Loc.initialize()
	for locale in Loc.SUPPORTED:
		Loc.set_locale(locale)
		for id in Loc.messages:
			if not (id.begins_with("menu.") or id.begins_with("daily.") or id.begins_with("crane.intro.") or id.begins_with("loading.")): continue
			if locale!="ru": assert(Loc.messages[id].translations.has(locale),id+":"+locale)
		assert(Loc.text("День 3")==Loc.message("daily.day")%3)
		assert(Loc.text("Забрать")==Loc.message("daily.claim"))
		assert(Loc.text("Пропущен")==Loc.message("daily.missed"))
		var spec = Catalog.crane_intro(100)
		assert(Loc.text(spec.title)==Loc.message("crane.intro.title"))
		var price:String=spec.blocks[3].text
		assert(price.contains("150") and price.contains("{{coin}}") and not price.contains("{price}"))
		assert(Text.line(price,preload("res://assets/fonts/MPLUSRounded1c-Bold.ttf"),20).get_objects().size()==1)
	Loc.set_locale("ar")
	assert(Loc.text("День 3")=="يوم 3")
	assert(Loc.text("Сегодня")=="اليوم")
	Loc.set_locale("fr")
	assert(Loc.text("Забрать")=="Récupérer")
	Loc.set_locale("ja")
	assert(Loc.text("Пропущен")=="受取期限切れ")
	print("Translation delta: all 11 locales, source aliases, crane price/icon and revised copy passed")
	quit()
