extends RefCounted
## ID-based translations. Source matching is a migration adapter for custom-drawn UI.
const SUPPORTED := ["ru","en","de","fr","ja","ko","zh","tr","pl","es","ar"]
static var locale := ""
static var messages:Dictionary = {}
static var sources:Dictionary = {}
static var formatted:Array = []
static var cache:Dictionary = {}

static func initialize() -> void:
	if not locale.is_empty(): return
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://localization/runtime.json"))
	messages = data.get("messages",{}) if data is Dictionary else {}
	for id in messages:
		var source:String = messages[id].source
		sources[source] = id
		if not source.contains("%") or source.contains("${"): continue
		# Only templates with actual source words; never match arbitrary numbers/text.
		var words := RegEx.new()
		words.compile("[А-Яа-яЁё]")
		if words.search(source)==null: continue
		var token := RegEx.new()
		token.compile("%(?:0?[0-9]+)?[dsf]")
		var pattern := "^"
		var offset := 0
		var types:Array[String] = []
		for m in token.search_all(source):
			pattern += escape_regex(source.substr(offset,m.get_start()-offset))
			var kind:String = m.get_string().right(1)
			pattern += "(-?[0-9]+)" if kind=="d" else ("(-?[0-9.]+)" if kind=="f" else "(.+?)")
			types.append(kind)
			offset = m.get_end()
		pattern += escape_regex(source.substr(offset))+"$"
		var rx := RegEx.new()
		if rx.compile(pattern)==OK: formatted.append({"id":id,"regex":rx,"types":types})
	var requested := OS.get_locale_language()
	if OS.has_feature("web"):
		var web_locale = JavaScriptBridge.eval("new URLSearchParams(location.search).get('lang') || navigator.language",true)
		if web_locale is String: requested = web_locale
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--language="): requested = arg.trim_prefix("--language=")
	set_locale(requested)

static func escape_regex(value:String) -> String:
	var result := ""
	for ch in value:
		if ch in "\\.^$|?*+()[]{}": result += "\\"
		result += ch
	return result

static func set_locale(value:String) -> void:
	locale = value.to_lower().replace("_","-").get_slice("-",0)
	if locale not in SUPPORTED: locale = "en"
	TranslationServer.set_locale(locale)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try { localStorage.setItem('cargo-language', " + JSON.stringify(locale) + "); } catch (_) {}",true)
	cache.clear()
	var fallback_paths := {"ar":"NotoSansArabic","ko":"NotoSansKR","zh":"NotoSansSC"}
	var fallback:Font = null
	if fallback_paths.has(locale): fallback = load("res://assets/fonts/localization/"+fallback_paths[locale]+".ttf")
	for weight in ["Medium","Bold","ExtraBold","Black"]:
		var base:Font = load("res://assets/fonts/MPLUSRounded1c-"+weight+".ttf")
		base.fallbacks = [fallback] if fallback else []

static func message(id:String,parameters:Dictionary={}) -> String:
	initialize()
	if not messages.has(id): return id
	var item:Dictionary = messages[id]
	var fallback:String=item.source if locale=="ru" else item.translations.get("en",item.source)
	var value:String = item.translations.get(locale,fallback)
	# One-pass named replacements cannot recursively interpret inserted values.
	var rx := RegEx.new()
	rx.compile("(?<!\\{)\\{([a-zA-Z_][a-zA-Z0-9_]*)\\}(?!\\})")
	var result := ""
	var offset := 0
	for m in rx.search_all(value):
		result += value.substr(offset,m.get_start()-offset)+str(parameters.get(m.get_string(1),m.get_string()))
		offset = m.get_end()
	return result+value.substr(offset)

static func text(value:String) -> String:
	initialize()
	if cache.has(value): return cache[value]
	var result := value
	if sources.has(value): result = message(sources[value])
	else:
		for rule in formatted:
			var found = rule.regex.search(value)
			if found==null: continue
			var args:Array = []
			for i in rule.types.size():
				var v:String = found.get_string(i+1)
				args.append(int(v) if rule.types[i]=="d" else (float(v) if rule.types[i]=="f" else text(v)))
			result = message(rule.id)%args
			break
	if cache.size()>512: cache.clear()
	cache[value] = result
	return result
