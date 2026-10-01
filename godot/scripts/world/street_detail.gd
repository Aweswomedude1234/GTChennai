class_name StreetDetail
extends RefCounted
## Street furniture and clutter generated per near chunk from the road graph and building
## frontage (Phase 2 fills this out: poles, cables, street lights, trees, parked two-wheelers,
## posters, compound walls…). Runs on worker threads like BuildingGen.

var pack: CityPack

func _init(p: CityPack) -> void:
	pack = p

func build_chunk(_key: String, _center: Vector2, _ctx: BuildingGen.Ctx) -> void:
	pass

func attach_chunk(_node: Node3D, _ctx: BuildingGen.Ctx) -> void:
	pass
