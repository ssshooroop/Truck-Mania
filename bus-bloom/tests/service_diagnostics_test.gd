extends SceneTree
const Diagnostics = preload("res://scripts/ui/service_diagnostics.gd")
const Menu = preload("res://scripts/ui/menu_windows.gd")
const Modal = preload("res://scripts/ui/game_modal.gd")
const Main = preload("res://scripts/main.gd")
const Loc = preload("res://scripts/localization.gd")
const Text = preload("res://scripts/ui/localized_text.gd")
const Style = preload("res://scripts/ui/modal_style.gd")
var checks := 0
var failures := 0

class MockAds extends RefCounted:
	var config := {"android_game_id":"123456789","test_mode":false,"rewarded":{"shop":"shop_unit","double":"double_unit"},
		"interstitial":"interstitial_unit","secret":"CONFIG_SECRET_SHOULD_NOT_APPEAR"}
	var initialized := false
	var init_error := "sdk_17: connection failed"
	var last_error := ""
	var errors_by_unit := {"shop_unit":"sdk_44: no fill","double_unit":""}
	var ready := {"shop_unit":false,"double_unit":true}
	var retry_pending := {"shop_unit":true}
	var init_retry_pending := true
	var account_id := "ACCOUNT_SECRET_SHOULD_NOT_APPEAR"

class MockStore extends RefCounted:
	var state := "ready"
	var initialized := true
	var loading := false
	var buying := false
	var last_error := "huawei_60055"
	var products := {"coins_500":{},"coins_1200":{},"starter":{}}
	var available := ["coins_500","starter"]
	var _pending_receipts := {"TOKEN_SECRET_SHOULD_NOT_APPEAR":{"order_id":"ORDER_SECRET_SHOULD_NOT_APPEAR"}}
	var player_id := "PLAYER_SECRET_SHOULD_NOT_APPEAR"
	func is_available(id:String="") -> bool: return initialized and not buying and id in available

func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _initialize() -> void: run.call_deferred()

func run() -> void:
	Loc.initialize()
	var ads := MockAds.new()
	var store := MockStore.new()
	var build := {"version":"huawei-v9-test","version_name":"0.1.4","version_code":9.0,
		"package_name":"org.truckmania.game.hw","distribution":"huawei_appgallery",
		"player_id":"BUILD_PLAYER_SECRET_SHOULD_NOT_APPEAR"}
	var settings := {"app_id":"119855549","package_name":"org.truckmania.game.hw",
		"public_key":"PUBLIC_KEY_SHOULD_NOT_APPEAR","private_key":"PRIVATE_KEY_SHOULD_NOT_APPEAR",
		"product_ids":{"coins_500":"huawei.coins500","coins_1200":"huawei.coins1200","starter":"huawei.starter"}}
	var result := Diagnostics.snapshot(build,ads,store,settings)
	check(result.build.version_code==9 and result.build.version=="huawei-v9-test","JSON numeric version code and build tag are retained")
	check(result.build.package_name=="org.truckmania.game.hw" and result.store.configured_app_id=="119855549","Report names embedded package and configured App ID")
	check(result.store.configured_product_count==3 and result.store.available_product_count==2,
		"Configured and available product counts remain distinct")
	check(result.store.available_products==["coins_500","starter"] and result.store.configured_products.starter=="huawei.starter",
		"Report includes public configured SKU mappings and current availability")
	check(result.ads.initialization_error=="sdk_17: connection failed" and result.ads.initialization_retry_pending,
		"Initialization error and retry state are exposed")
	check(result.ads.placements.shop.error=="sdk_44: no fill" and not result.ads.placements.shop.ready and result.ads.placements.shop.retry_pending,
		"Shop placement error survives an unrelated successful load and empty global error")
	check(result.ads.placements.double.ready and result.ads.placements.double.error.is_empty(),"Per-placement readiness is independent")
	check(result.store.last_error=="huawei_60055","Huawei numeric error code survives redaction")
	check(result.platform.has("version") and result.platform.has("iap_plugin_present") and result.platform.has("ads_plugin_present"),
		"Platform and native singleton presence are available without USB")
	var text := JSON.stringify(result)
	check(not text.contains("SHOULD_NOT_APPEAR") and not text.contains("public_key") and not text.contains("_pending_receipts"),
		"Whitelisting omits keys, receipts, tokens, orders, raw config and personal identifiers")
	store.available = ["coins_1200"]
	check(Diagnostics.snapshot(build,ads,store,settings).store.available_products==["coins_1200"],
		"Each report observes the latest service state")
	var absent := RefCounted.new()
	var missing := Diagnostics.snapshot({},absent,null)
	check(missing.ads.initialization_error=="" and missing.store.available_product_count==0 and missing.store.state=="unavailable",
		"Absent optional fields and services are handled without exceptions")
	check(not Diagnostics.report({},null,null).strip_edges().is_empty(),"Real report is nonempty even without SDK services")

	var cases := [
		["sdk_7: failed https://user:URL_PASSWORD@example.org/pay?token=QUERY_SECRET","URL_PASSWORD"],
		["sdk_7: failed https://example.org/pay?token=QUERY_SECRET","QUERY_SECRET"],
		["sdk_7: https%3A%2F%2Fexample.org%2Fpay%3Ftoken%3DENCODED_SECRET","ENCODED_SECRET"],
		["sdk_7: endpoint?session=SHORT_SESSION","SHORT_SESSION"],
		["sdk_7: Authorization: Bearer HEADER_SECRET\nno fill","HEADER_SECRET"],
		["sdk_7: Cookie: account=COOKIE_SECRET\nno fill","COOKIE_SECRET"],
		["sdk_7: X-Api-Key: API_SECRET\nno fill","API_SECRET"],
		["sdk_7: {\"purchaseToken\":\"PURCHASE_SECRET\"}","PURCHASE_SECRET"],
		["sdk_7: order_id=ORDER_SECRET, no fill","ORDER_SECRET"],
		["sdk_7: account_id='ACCOUNT_SECRET' no fill","ACCOUNT_SECRET"],
		["sdk_7: email=private.person@example.com","private.person@example.com"],
		["sdk_7: contact private.person@example.com","private.person@example.com"],
		["sdk_7: Bearer BEARER_SECRET","BEARER_SECRET"],
		["sdk_7: "+"LONG_TOKEN_".repeat(12),"LONG_TOKEN_"],
		["sdk_7: -----BEGIN PUBLIC KEY-----\nPEM_SECRET\n-----END PUBLIC KEY-----","PEM_SECRET"],
		["sdk_7: id aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee","aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"],
		["sdk_7: device 123456789012345","123456789012345"]]
	for item:Array in cases:
		var clean := Diagnostics.sanitize_error(item[0])
		check(clean.begins_with("sdk_7:") and not clean.contains(item[1]),"Error redaction preserves SDK code while removing sensitive content: "+str(cases.find(item)))
	check(Diagnostics.sanitize_error("load_timeout")=="load_timeout","Useful non-sensitive error codes are unchanged")
	for code:String in ["configuration_invalid_IllegalArgumentException","configuration_invalid_InvalidKeySpecException",
		"configuration_invalid_NoSuchAlgorithmException","configuration_invalid_NameNotFoundException"]:
		check(Diagnostics.sanitize_error(code)==code,"Known fixed configuration error survives token redaction: "+code)
		check(not Diagnostics.sanitize_error(code+" token=APPENDED_SECRET").contains("APPENDED_SECRET"),
			"Known configuration prefix does not exempt appended credentials")
	check(Diagnostics.sanitize_error("  configuration_invalid_InvalidKeySpecException\n")=="configuration_invalid_InvalidKeySpecException",
		"Whitespace around an exact fixed code is harmless")
	check(not Diagnostics.sanitize_error("configuration_invalid_IllegalArgumentException_"+"TOKEN_SUFFIX".repeat(8)).contains("TOKEN_SUFFIX"),
		"Credential suffix cannot use the configuration-code allowlist")
	check(not Diagnostics.sanitize_error("configuration_invalid_ArbitrarySensitiveExceptionName").contains("ArbitrarySensitiveExceptionName"),
		"Arbitrary exception-like strings retain ordinary long-token redaction")
	check(Diagnostics.sanitize_error({"token":"never stringify me"}).is_empty(),"Unexpected structured errors are never stringified")
	check(Diagnostics.sanitize_error("word ".repeat(3000)).length()<=Diagnostics.MAX_ERROR_LENGTH+1,"Error text and redaction work are bounded")
	check(not Diagnostics.sanitize_error("sdk_7:\u202eerror\n\tfailed").contains("\u202e"),"Diagnostic errors remove bidi controls and control characters")

	# Verify the complete support layout in every locale, on phone and tablet.
	for language:String in Loc.SUPPORTED:
		Loc.set_locale(language)
		for source:String in ["Скопировать диагностику","Диагностика скопирована"]:
			check(not Loc.text(source).is_empty() and (language=="ru" or Loc.text(source)!=source),"Diagnostics text is translated: "+language)
		for viewport:Vector2 in [Vector2(540,720),Vector2(540,1171),Vector2(1200,800)]:
			var modal = Modal.new(Menu.support("huawei-v9-20261118","test-player"))
			root.add_child(modal)
			modal.set_anchors_preset(Control.PRESET_TOP_LEFT)
			modal.size = viewport
			modal.age = 1.0
			modal._layout()
			var card:Rect2 = modal.base*modal.card_rect
			check(card.position.y>=0 and card.end.y<=viewport.y and card.position.x>=0 and card.end.x<=viewport.x,
				"Support card fits viewport: "+language+str(viewport))
			check(modal.hits.has("copy_diagnostics") and modal.hits.has("copy") and modal.hits.has("send"),"All support actions remain available")
			for placed:Dictionary in modal.placed:
				if placed.block.get("id","")!="copy_diagnostics": continue
				check(Text.width(placed.block.label,Style.HEAVY,21)<=placed.rect.size.x,"Diagnostics link fits without clipping: "+language)
			modal.free()

	Loc.set_locale("ru")
	# Some desktop sandboxes advertise clipboard support but isolate the native
	# clipboard. Verify a control write before asserting the integration result.
	var clipboard_available := false
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set("diagnostics-test-clipboard-probe")
		await process_frame
		clipboard_available = DisplayServer.clipboard_get()=="diagnostics-test-clipboard-probe"
		if not clipboard_available: print("SKIP: native clipboard is unavailable in this test environment")
	var game = Main.new()
	game.automation = true
	game.save_enabled = false
	root.add_child(game)
	game._show_road_menu(false)
	game._open_support()
	await process_frame
	await process_frame
	check(game.modal.message_input.text.is_empty(),"Support starts with an empty message")
	check(game.modal.tap("copy_diagnostics") and game.modal.flash_text=="Диагностика скопирована",
		"Diagnostics copies through its own action without the empty-message guard")
	if clipboard_available:
		await process_frame
		var copied := DisplayServer.clipboard_get().replace("\r\n","\n")
		check(copied.begins_with("Truck Mania diagnostics\n") and copied.contains("initialization_error"),"Support action copies the report to the clipboard")
		check(not copied.contains(game.player_id) if not game.player_id.is_empty() else true,"Copied diagnostics exclude player ID")
	game.modal.tap("copy")
	check(game.modal.flash_text=="Напишите сообщение","Existing message-copy guard remains unchanged")
	game.modal.message_input.text = "User message must stay in the editor"
	game.modal.tap("copy_diagnostics")
	check(game.modal.message_input.text=="User message must stay in the editor","Diagnostics action preserves the user's message")
	if "--capture-support" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute("res://artifacts/support-diagnostics")
		for language:String in ["ru","de","ar"]:
			Loc.set_locale(language)
			for viewport:Vector2i in [Vector2i(540,720),Vector2i(1200,800)]:
				root.content_scale_size = viewport
				root.size = viewport
				game._open_support()
				game.modal.age = 1.0
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://artifacts/support-diagnostics/%s-%dx%d.png" % [language,viewport.x,viewport.y])
	game.queue_free()
	await process_frame
	print("SERVICE_DIAGNOSTICS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
