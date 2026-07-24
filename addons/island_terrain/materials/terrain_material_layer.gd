@tool
extends Resource
class_name IslandTerrainMaterialLayer

@export var display_name: StringName = &"Layer"
@export_range(0, 7, 1) var atlas_slot: int = 0
@export var tint: Color = Color.WHITE
@export_range(0.25, 64.0, 0.25) var meters_per_tile: float = 4.0
@export_range(0.0, 1.0, 0.01) var roughness: float = 0.90
@export_range(0.0, 1.0, 0.01) var metallic: float = 0.0
@export_range(0.0, 2.0, 0.01) var normal_strength: float = 1.0


func sanitize(max_slots: int = 8) -> void:
	atlas_slot = clampi(atlas_slot, 0, maxi(0, max_slots - 1))
	meters_per_tile = clampf(meters_per_tile, 0.25, 64.0)
	roughness = clampf(roughness, 0.0, 1.0)
	metallic = clampf(metallic, 0.0, 1.0)
	normal_strength = clampf(normal_strength, 0.0, 2.0)
