extends SceneTree
func _initialize():
 for setting in ProjectSettings.get_property_list():
  if "blender" in str(setting.name): print(setting.name," = ",ProjectSettings.get(setting.name))
 quit()
