from pathlib import Path

path = Path("addons/island_terrain/island_terrain_3d.gd")
text = path.read_text()

old = '''func get_material_working_memory_bytes() -> int:
\tvar metadata_bytes: int = _material_runtime.estimated_working_memory_bytes() if _material_runtime != null else 0
\tvar override_bytes: int = _material_override_sync.estimated_memory_bytes() if _material_override_sync != null else 0
\treturn metadata_bytes + override_bytes


func get_material_override_texture()'''
new = '''func get_material_working_memory_bytes() -> int:
\treturn _material_runtime.estimated_working_memory_bytes() if _material_runtime != null else 0


func get_material_resident_memory_bytes() -> int:
\treturn _material_override_sync.estimated_memory_bytes() if _material_override_sync != null else 0


func get_material_override_texture()'''
if new not in text:
    if text.count(old) != 1:
        raise SystemExit(f"material memory API: expected one match, found {text.count(old)}")
    text = text.replace(old, new, 1)

old = '''func _metric_resident_memory_bytes() -> int:
\treturn _metric_region_cache_bytes() + get_material_working_memory_bytes()'''
new = '''func _metric_resident_memory_bytes() -> int:
\treturn _metric_region_cache_bytes() \\
\t\t+ get_material_working_memory_bytes() \\
\t\t+ get_material_resident_memory_bytes()'''
if new not in text:
    if text.count(old) != 1:
        raise SystemExit(f"resident metric: expected one match, found {text.count(old)}")
    text = text.replace(old, new, 1)

path.write_text(text)
