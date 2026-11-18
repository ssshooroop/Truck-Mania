@tool
extends EditorPlugin

var exporter: EditorExportPlugin

func _enter_tree() -> void:
	exporter = HuaweiIapExport.new()
	add_export_plugin(exporter)

func _exit_tree() -> void:
	remove_export_plugin(exporter)

class HuaweiIapExport extends EditorExportPlugin:
	func _get_name() -> String:
		return "TruckManiaIap"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _is_huawei_export() -> bool:
		var preset := get_export_preset()
		if preset == null: return false
		for feature in preset.get_custom_features().split(",", false):
			if feature.strip_edges() == "huawei_appgallery": return true
		return false

	func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(["huawei_iap/truck-mania-iap.aar"]) if _is_huawei_export() else PackedStringArray()

	func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(["com.huawei.hms:iap:6.16.6.305"]) if _is_huawei_export() else PackedStringArray()

	func _get_android_dependencies_maven_repos(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(["https://developer.huawei.com/repo/"]) if _is_huawei_export() else PackedStringArray()

	func _get_android_manifest_application_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
		if not _is_huawei_export(): return ""
		var config = JSON.parse_string(FileAccess.get_file_as_string("res://config/huawei_iap.json"))
		if not config is Dictionary: return ""
		var app_id := str(config.get("app_id", ""))
		if app_id.is_empty() or not app_id.is_valid_int(): return ""
		return '<meta-data android:name="com.huawei.hms.client.appid" android:value="appid=%s" />' % app_id.xml_escape(true)
