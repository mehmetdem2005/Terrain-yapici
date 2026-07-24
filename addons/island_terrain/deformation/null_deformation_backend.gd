@tool
extends "res://addons/island_terrain/deformation/terrain_deformation_backend.gd"
class_name IslandTerrainNullDeformationBackend

# Deliberate no-op backend used until the sparse voxel/SDF phase is enabled.
# Keeping this concrete type prevents gameplay/editor code from branching on
# null references and preserves the deformation interface from milestone one.
