extends SceneTree
func _initialize() -> void:
	var output = []
	for file in ["citypack.fbx","Free Pack - Tree.fbx","Low-Poly Industrial & Factory Pack.fbx"]:
		var scene = load("res://assets/artwork/3D/"+file).instantiate()
		var nodes = scene.find_children("*","MeshInstance3D",true,false)
		var entries = []
		for node:MeshInstance3D in nodes:
			var mats = []
			for i in node.mesh.get_surface_count():
				var mat = node.get_active_material(i)
				mats.append({"name":mat.resource_name if mat else "none","color":str(mat.albedo_color) if mat is BaseMaterial3D else "", "texture":mat.albedo_texture.resource_path if mat is BaseMaterial3D and mat.albedo_texture else ""})
			entries.append({"path":str(scene.get_path_to(node)),"bounds":str(node.get_aabb()),"transform":str(node.transform),"materials":mats})
		output.append({"file":file,"meshes":entries})
		scene.free()
	FileAccess.open("res://artifacts/prop-catalog.json",FileAccess.WRITE).store_string(JSON.stringify(output,"\t"))
	quit()
