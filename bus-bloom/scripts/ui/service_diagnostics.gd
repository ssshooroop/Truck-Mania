extends RefCounted
## Explicit Support export only. Never serialize a service, configuration,
## receipt, transaction ledger or device/player identifier into the report.
const MAX_ERROR_LENGTH := 320
const MAX_IDENTIFIERS := 32
const PLACEMENTS := ["shop","shortfall","double","slot","undo"]
const KNOWN_CONFIGURATION_ERRORS := [
	"configuration_invalid_IllegalArgumentException",
	"configuration_invalid_InvalidKeySpecException",
	"configuration_invalid_NoSuchAlgorithmException",
	"configuration_invalid_NameNotFoundException"]

static func report(build:Dictionary,ads:Object,store:Object) -> String:
	var settings:Dictionary = {}
	var path := "res://config/huawei_iap.json"
	if FileAccess.file_exists(path):
		var parsed:Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary: settings = parsed
	return "Truck Mania diagnostics\n"+JSON.stringify(snapshot(build,ads,store,settings),"  ")

static func snapshot(build:Dictionary,ads:Object,store:Object,settings:Dictionary={}) -> Dictionary:
	var build_fields := {}
	for field:String in ["version","version_name","distribution","package_name"]:
		build_fields[field] = _identifier(build.get(field,""))
	var code:Variant = build.get("version_code",0)
	build_fields.version_code = int(code) if (code is int or code is float) and is_finite(float(code)) and float(code)>=0 and float(code)<=2147483647 and float(code)==float(int(code)) else 0
	var ads_config := _dictionary(_property(ads,"config",{}))
	var units := _dictionary(ads_config.get("rewarded",{}))
	var ready := _dictionary(_property(ads,"ready",{}))
	var errors := _dictionary(_property(ads,"errors_by_unit",{}))
	var retries := _dictionary(_property(ads,"retry_pending",{}))
	var placements := {}
	for placement:String in PLACEMENTS:
		var unit := _identifier(units.get(placement,""))
		placements[placement] = _ad_unit(unit,ready,errors,retries)
	placements.interstitial = _ad_unit(_identifier(ads_config.get("interstitial","")),ready,errors,retries)
	var configured := _identifier_map(settings.get("product_ids",{}))
	var products := _dictionary(_property(store,"products",{}))
	var available:Array[String] = []
	var candidates:Array = configured.keys() if not configured.is_empty() else products.keys()
	candidates.sort()
	for id:Variant in candidates.slice(0,MAX_IDENTIFIERS):
		var safe_id := _identifier(id)
		if safe_id.is_empty(): continue
		if is_instance_valid(store) and store.has_method("is_available") and store.call("is_available",safe_id)==true:
			available.append(safe_id)
	var state:Variant = _property(store,"state","unavailable")
	if state not in ["unavailable","initializing","loading_products","ready","error"]: state = "unknown"
	return {
		"schema":1,
		"build":build_fields,
		"platform":{"name":OS.get_name(),"version":sanitize_error(OS.get_version()),
			"huawei_appgallery":OS.has_feature("huawei_appgallery"),
			"ads_plugin_present":Engine.has_singleton("TruckManiaAds"),
			"iap_plugin_present":Engine.has_singleton("TruckManiaIap")},
		"ads":{"game_id":_identifier(ads_config.get("android_game_id","")),
			"test_mode":_flag(ads_config.get("test_mode",false)),
			"simulated":_flag(_property(ads,"simulate",false)),
			"initialized":_flag(_property(ads,"initialized",false)),
			"initialization_error":sanitize_error(_property(ads,"init_error","")),
			"last_error":sanitize_error(_property(ads,"last_error","")),
			"initialization_retry_pending":_flag(_property(ads,"init_retry_pending",false)),
			"watching":_flag(_property(ads,"watching",false)),"placements":placements},
		"store":{"state":state,"initialized":_flag(_property(store,"initialized",false)),
			"loading":_flag(_property(store,"loading",false)),"buying":_flag(_property(store,"buying",false)),
			"simulated":_flag(_property(store,"simulate",false)),
			"last_error":sanitize_error(_property(store,"last_error","")),
			"configured_app_id":_identifier(settings.get("app_id","")),
			"configured_package":_identifier(settings.get("package_name","")),
			"configured_products":configured,"configured_product_count":configured.size(),
			"available_products":available,"available_product_count":available.size()}
	}

static func _ad_unit(unit:String,ready:Dictionary,errors:Dictionary,retries:Dictionary) -> Dictionary:
	return {"unit":unit,"ready":_flag(ready.get(unit,false)),
		"error":sanitize_error(errors.get(unit,"")),"retry_pending":retries.has(unit)}

static func _property(value:Object,key:String,fallback:Variant) -> Variant:
	if is_instance_valid(value):
		for property:Dictionary in value.get_property_list():
			if property.name==key: return value.get(key)
	return fallback

static func _dictionary(value:Variant) -> Dictionary:
	return value if value is Dictionary else {}

static func _flag(value:Variant) -> bool:
	return value is bool and value

static func _identifier(value:Variant) -> String:
	if not value is String: return ""
	var rx := RegEx.new()
	rx.compile("^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$")
	return value if rx.search(value)!=null else ""

static func _identifier_map(value:Variant) -> Dictionary:
	var result := {}
	if not value is Dictionary: return result
	var keys:Array = value.keys().filter(func(key): return key is String)
	keys.sort()
	for key:String in keys.slice(0,MAX_IDENTIFIERS):
		var id := _identifier(key)
		var sku := _identifier(value[key])
		if not id.is_empty() and not sku.is_empty(): result[id] = sku
	return result

static func _replace(value:String,pattern:String,replacement:String) -> String:
	var rx := RegEx.new()
	if rx.compile(pattern)!=OK: return "[redacted]"
	return rx.sub(value,replacement,true)

static func sanitize_error(value:Variant) -> String:
	if not value is String: return ""
	# These fixed native codes exceed the generic token length. Exact matching
	# preserves them without exempting an appended message or credential.
	var exact_code:String = value.strip_edges()
	if exact_code in KNOWN_CONFIGURATION_ERRORS: return exact_code
	# Bound work before matching; truncated token/key fragments are still removed.
	var text:String = value.substr(0,8192)
	text = _replace(text,"(?is)-----BEGIN [^-]*KEY-----.*?(?:-----END [^-]*KEY-----|$)","[key redacted]")
	text = _replace(text,"(?i)\\b(?:https?|wss?|ftp)://[^\\s<>\"']+|(?:https?|wss?)%3a%2f%2f[^\\s]+","[url redacted]")
	text = _replace(text,"(?i)\\b(?:authorization|proxy-authorization|cookie|set-cookie|x-api-key|x-auth-token)\\s*[:=][^\\r\\n]*","[header redacted]")
	text = _replace(text,"(?i)[\"']?\\b(?:purchase[_ -]?token|access[_ -]?token|refresh[_ -]?token|id[_ -]?token|token|password|secret|signature|public[_ -]?key|private[_ -]?key|api[_ -]?key|client[_ -]?secret|order[_ -]?id|player[_ -]?id|device[_ -]?id|account[_ -]?id|user[_ -]?id|email|phone)[\"']?\\s*[:=]\\s*(?:\"[^\"\\r\\n]*\"|'[^'\\r\\n]*'|[^\\s,;}&]+)","[value redacted]")
	text = _replace(text,"(?i)\\b(?:Bearer|Basic)\\s+[A-Za-z0-9+/_.=:-]+","[credential redacted]")
	text = _replace(text,"\\?[^\\s<>\"']+","?[query redacted]")
	text = _replace(text,"(?i)\\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}\\b","[email redacted]")
	text = _replace(text,"(?i)\\b[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\\b","[identifier redacted]")
	text = _replace(text,"[A-Za-z0-9_+/=.-]{40,}|\\b[0-9]{12,}\\b","[identifier redacted]")
	text = _replace(text,"[\\x{0000}-\\x{001f}\\x{007f}\\x{202a}-\\x{202e}\\x{2066}-\\x{2069}]"," ")
	text = _replace(text,"\\s+"," ").strip_edges()
	return text.substr(0,MAX_ERROR_LENGTH)+("…" if text.length()>MAX_ERROR_LENGTH else "")
