extends SceneTree
## Bakes every bomber-bot glb into <id>-merged.res: the parts merged into a
## few surfaces (vertex colours, grouped by finish) with LODs, so the game
## never has to simplify meshes at runtime (web templates may lack the
## simplifier). Run after changing a bot model:
##   godot --headless --path godot --script res://scripts/tools/bake_bots.gd

const ModelBot := preload("res://scripts/model_bot.gd")


func _init() -> void:
	var dir := DirAccess.open("res://assets/characters")
	for f in dir.get_files():
		if not f.ends_with(".glb"):
			continue
		var path := "res://assets/characters/" + f
		var scene: PackedScene = load(path)
		var mesh: ArrayMesh = ModelBot._merge(scene.instantiate())
		var out := path.get_basename() + "-merged.res"
		var tris := 0
		for s in mesh.get_surface_count():
			tris += (mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		var err := ResourceSaver.save(mesh, out, ResourceSaver.FLAG_COMPRESS)
		print("baked %s: %d surfaces, %d triangles, err %d" % [out, mesh.get_surface_count(), tris, err])
	quit()
