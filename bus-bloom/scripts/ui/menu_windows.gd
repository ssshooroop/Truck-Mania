extends RefCounted
const Style = preload("res://scripts/ui/modal_style.gd")
const Loc = preload("res://scripts/localization.gd")
const LANGUAGES = [["ru","Русский"],["en","English"],["de","Deutsch"],["fr","Français"],["es","Español"],["pl","Polski"],["tr","Türkçe"],["ja","日本語"],["ko","한국어"],["zh","简体中文"],["ar","العربية"]]
static func languages() -> Dictionary:
	return {"id":"language","title":"Язык","close":true,"back":"close","blocks":[{"type":"languages","items":LANGUAGES,"selected":Loc.locale}]}
static func support(version:String,player_id:String) -> Dictionary:
	return {"id":"support","title":"Поддержка","close":true,"back":"close","blocks":[
		{"type":"hero","texture":preload("res://assets/artwork/billy/billy-thinking.png"),"size":105,"rays":false},
		{"type":"text","text":"Нашли ошибку или есть идея?\nНапишите — читаем каждое письмо.","size":22},
		{"type":"input","id":"message"},
		{"type":"text","text":Loc.text("Версия: %s\nID: %s")%[version,player_id],"size":14},
		{"type":"button","id":"send","kind":"primary","label":"Открыть письмо"},
		{"type":"link","id":"copy","label":"Скопировать сообщение"},
		{"type":"link","id":"copy_diagnostics","label":"Скопировать диагностику"}]}
