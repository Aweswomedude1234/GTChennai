extends SceneTree
func _initialize() -> void:
	for id in ["man_00", "woman_01"]:
		var n: Node = (load("res://assets/humans/%s.glb" % id) as PackedScene).instantiate()
		var tot := 0
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			var m: Mesh = mi.mesh
			for s in m.get_surface_count():
				var a := m.surface_get_arrays(s)
				var nv: int = (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
				tot += nv
				print(id, " ", mi.name, " s", s, " verts ", nv, " bones ", (a[Mesh.ARRAY_BONES] as PackedInt32Array).size() / maxi(nv, 1) if a[Mesh.ARRAY_BONES] else 0, " blend ", m.get_blend_shape_count(), " fmt ", m.surface_get_format(s))
		print(id, " total verts ", tot)
		n.free()
	quit()
