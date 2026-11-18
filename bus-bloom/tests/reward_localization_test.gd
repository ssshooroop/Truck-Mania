extends SceneTree
const L=preload("res://scripts/localization.gd")
const C=preload("res://scripts/ui/modal_catalog.gd")
func _initialize():
	L.initialize()
	var cyrillic=RegEx.new();cyrillic.compile("[А-Яа-яЁё]")
	for language in L.SUPPORTED:
		L.set_locale(language)
		var text=C.reward_parts({"base":25,"streak":25,"chest":10,"achievements":5})
		assert(text.contains("+25") and text.contains("+10") and text.contains("+5"))
		if language!="ru":assert(cyrillic.search(text)==null,"Russian reward label in "+language)
		if language=="ja":assert(text.begins_with("レベル +25 · 連続 +25"))
		var offer=C.offer("undo",20,50,false)
		for block in offer.blocks:
			for key in ["label","text"]:
				if block.has(key) and language!="ru":assert(cyrillic.search(L.text(block[key]))==null)
	print("Reward components and undo offer: all 11 locales passed")
	quit()

