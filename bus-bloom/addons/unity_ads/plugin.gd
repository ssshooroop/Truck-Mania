@tool
extends EditorPlugin
var exporter:EditorExportPlugin
func _enter_tree() -> void:
	exporter = AndroidAdsExport.new()
	add_export_plugin(exporter)
func _exit_tree() -> void:
	remove_export_plugin(exporter)
class AndroidAdsExport extends EditorExportPlugin:
	func _get_name() -> String: return "TruckManiaAds"
	func _supports_platform(platform:EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid
	func _get_android_libraries(_platform:EditorExportPlatform,_debug:bool) -> PackedStringArray:
		return PackedStringArray(["unity_ads/truck-mania-ads.aar"])
	func _get_android_dependencies(_platform:EditorExportPlatform,_debug:bool) -> PackedStringArray:
		return PackedStringArray(["com.unity3d.ads:unity-ads:4.21.0"])
