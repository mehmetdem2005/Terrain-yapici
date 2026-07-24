# IslandTerrain Foundation

Godot 4.6.3 Mobile Renderer için 4 km hayatta kalma adası terrain altyapısı.

## Mevcut temel

- 4 km dünya ve 256 m region düzeni
- 257×257 region height verisi
- Sparse material, biome, wetness, hole ve foliage kanalları
- Canlı RAM muhasebesi ve temiz-region LRU tahliyesi
- Kirli region veri koruması
- `res://` kaynak ve `user://` runtime copy-on-write depolama
- Geçici dosya, checksum, yedek ve terfi kullanan atomik kayıt
- Geometry clipmap merkez grid’i, içi boş LOD halkaları ve dış etekler
- Kare başına en fazla bir LOD oluşturma
- Tek ShaderMaterial ve instance LOD uniform’ları
- Satır bazlı, kare bütçeli ada önizleme üretimi
- Gelecekteki sparse voxel/SDF kazma backend sözleşmesi

## Mobil profiller

| Profil | Makro height | LOD | Base quads | Cache | Shadow LOD | CPU bütçesi |
|---|---:|---:|---:|---:|---:|---:|
| Low | 257² | 5 | 48 | 5 | 1 | 1 ms |
| Balanced | 257² | 6 | 64 | 9 | 2 | 2 ms |
| High | 513² | 7 | 80 | 25 | 4 | 3 ms |
| Editor Preview | 513² | 7 | 64 | 9 | 2 | 2 ms |

Telefonlarda varsayılan profil `Balanced` olmalıdır. `High` yalnızca profiler sonucu uygunsa kullanılmalıdır.

## Kullanım

1. Godot’ta **Project > Project Settings > Plugins** bölümünden `IslandTerrain` eklentisini etkinleştir.
2. 3D sahneye `IslandTerrain3D` node’u ekle.
3. Renderer ayarını `Mobile` olarak bırak.
4. Terrain node’unu taşıyabilirsin; rotation kimlik, scale `Vector3.ONE` kalmalıdır.

## Test

```bash
godot --headless --path . --editor --quit-after 3
godot --headless --path . --script addons/island_terrain/test/foundation_test.gd
```

## Mimari sınırlar

- Renderer dosya sistemine erişmez.
- Persistence sahne node’u veya render RID’i yönetmez.
- Tüm dünya/region dönüşümleri tek koordinat servisi üzerinden geçer.
- Büyük 4097² runtime heightmap oluşturulmaz.
- Kazma sistemi heightfield koduna bağlanmaz; deformation interface üzerinden eklenir.
