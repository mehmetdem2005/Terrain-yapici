# IslandTerrain 0.5

Godot 4.6.3 Mobile Renderer için 4 km hayatta kalma adası terrain editörü.

## Çekirdek

- 4 km dünya ve 256 m region düzeni
- 257×257 region height verisi
- Sparse height, biome, material, wetness, hole ve foliage kanalları
- Canlı RAM muhasebesi ve temiz-region LRU tahliyesi
- Kirli region veri koruması
- `res://` kaynak ve `user://` runtime copy-on-write depolama
- Geçici dosya, birleşik checksum, yedek ve terfi kullanan atomik kayıt
- Region format v1/v2 → v3 migration
- Geometry clipmap merkez grid’i, içi boş LOD halkaları ve dış etekler
- Kare başına en fazla bir LOD oluşturma
- Tek ShaderMaterial ve instance LOD uniform’ları
- Gelecekteki sparse voxel/SDF kazma backend sözleşmesi

## Ada generation graph

`IslandTerrainGenerationController`, cihaz profilindeki kare bütçesini kullanarak şu aşamaları sırayla işletir:

```text
Kıyı ve ana yükselti
  → Termal erozyon
  → Akış yönü
  → Sabit-dizili counting sort
  → Flow accumulation
  → Nehir oyma
  → Nem ve biyom sınıflandırması
```

Akış sıralaması piksel başına dinamik bucket veya packed-array kopyası oluşturmaz. 4096 sabit yükseklik kovası, counting-sort offset dizileri ve kare bütçeli accumulation kullanılır.

Generation sonucu normalize height, moisture, biome, river mask ve flow accumulation kanallarını taşır. Bu metadata her region’a kopyalanmaz. Dünya sorguları:

- `get_biome_at_world()`
- `get_moisture_at_world()`
- `get_river_mask_at_world()`
- `get_flow_accumulation_at_world()`

## Biyom material sistemi

`IslandTerrainMaterialRuntime`, generation metadata’sını RGBA8 texture’a kare bütçeli biçimde encode eder:

- R: biyom kimliği
- G: nem
- B: nehir maskesi
- A: log-normalize flow accumulation

Varsayılan backend `Atlas`tır. Bu, Android cihazlarda texture-array sürücü uyumsuzluğu riskini azaltır. `Texture2DArray` atanırsa aynı shader array backend’ini kullanabilir; array eksikse otomatik olarak atlas veya color-only fallback’e geçilir.

Altı temel katman bulunur: Sand, Grass, Forest, Wetland, Rock ve Mountain. Her katmanda tint, atlas slotu, metre başına döşeme ölçeği, roughness ve metallic ayarlanabilir. Kullanıcı atlas vermemişse deterministic nötr fallback atlas üretilir.

Yakın LOD’lar atlas veya texture array örnekler. `detail_lod_limit` üzerindeki uzak LOD’lar yalnızca katman tint’i kullanır; böylece uzakta texture fetch maliyeti kesilir.

Public API:

- `refresh_material_library()`
- `get_effective_material_backend()`
- `get_material_metadata_texture()`
- `get_material_override_texture()`
- `flush_material_override_sync()`
- `get_material_working_memory_bytes()`

## Region biyom ve material paint

Manuel paint, prosedürel generation metadata’sını değiştirmez. Region dosyalarında yüksek çözünürlüklü sparse override tutulur; renderer için yalnızca küçük bir RGBA8 makro texture üretilir:

- R: manuel biyom kimliği / 7
- G: biyom karışım gücü
- B: manuel material kimliği / 5
- A: material karışım gücü

```text
Editor Input
  → TerrainPaintSession
  → TerrainPaintCommand
  → TerrainMaterialPaintService
  → TerrainRegionRepository
  → TerrainMaterialOverrideSync
```

Araçlar:

- Biyom boya
- Material boya
- Biyomu prosedürel tabana geri yükle
- Materialı prosedürel tabana geri yükle
- Tüm manuel paint’i geri yükle

Kullanılmayan region’larda paint dizileri tahsis edilmez. İlk gerçek paint işleminde kimlik ve blend maskeleri açılır. 257×257 bir region için tam biyom + material override yaklaşık 264 KB kullanır ve mevcut RAM bütçesine anında eklenir.

Bir stroke bütün region’ı veya dünyayı kopyalamaz. Yalnızca değişen `Rect2i` içindeki önce/sonra byte dizileri tutulur ve varsayılan stroke undo sınırı 8 MB’dir. Sınır aşılırsa son dab geri sarılır.

Read-only biyom/material sorguları boş region oluşturmaz. Önce cache, sonra yalnızca gerçekten mevcut kaynak/runtime region dosyaları kontrol edilir.

## Sculpt sistemi

Araçlar: Yükselt, Alçalt, Yumuşat ve Düzleştir.

```text
Editor Input
  → TerrainSculptSession
  → TerrainSculptCommand
  → TerrainEditService
  → TerrainRegionRepository
  → MacroHeightSync
```

Undo/redo bütün dünya veya bütün region kopyası saklamaz; yalnızca etkilenen `Rect2i` içindeki height ve validity değerlerini tutar. Prosedürel ada görüntüsü immutable base height olarak korunur.

Sculpt ve Paint modları karşılıklı dışlanır. Her ikisi aynı `EditorUndoRedoManager` nesne geçmişini kullanır; işlemler tek kronolojik geri-al zincirinde kalır.

## Streamed collision

Tüm adaya tek fizik şekli oluşturulmaz. `IslandTerrainCollisionService`, oyuncu veya aktif kamera çevresinde pool’lanmış `StaticBody3D + HeightMapShape3D` patch’leri yönetir.

- Patch: 64 × 64 metre
- Örnek aralığı: 1 metre
- Balanced aktif yarıçap: 96 metre
- Kare başına en fazla bir patch build
- Dairesel hedef kümesi
- Sculpt, undo ve redo sonrası yalnızca kesişen aktif patch rebuild’i
- Profil veya height texture değişiminde stale patch temizliği
- Collision node’larında ölçek kullanılmaz

## Mobil profiller

| Profil | Makro height/metadata | LOD | Base quads | Cache | Shadow LOD | Collision yarıçapı | CPU bütçesi |
|---|---:|---:|---:|---:|---:|---:|---:|
| Low | 257² | 5 | 48 | 5 | 1 | 64 m | 1 ms |
| Balanced | 257² | 6 | 64 | 9 | 2 | 96 m | 2 ms |
| High | 513² | 7 | 80 | 25 | 4 | 160 m | 3 ms |
| Editor Preview | 513² | 7 | 64 | 9 | 2 | 96 m | 2 ms |

Telefonlarda varsayılan profil `Balanced`, material backend `Atlas` olmalıdır. `High` ve `Texture Array` yalnızca profiler sonucu uygunsa kullanılmalıdır. Büyük 4097² runtime heightmap veya paint texture oluşturulmaz.

## Kullanım

1. **Project > Project Settings > Plugins** bölümünden `IslandTerrain` eklentisini etkinleştir.
2. 3D sahneye `IslandTerrain3D` node’u ekle.
3. Renderer ayarını `Mobile` olarak bırak.
4. `generation_profile` ve `material_library` ayarlarını düzenle.
5. Terrain node’unu seç.
6. Sol üst dock’tan Sculpt, sol alt dock’tan Paint modunu aç.
7. Tek parmak veya sol tık ile düzenle; ikinci parmak kamera kontrolüne ayrılır.
8. Runtime collision için `collision_target_path` alanını oyuncuya bağla.

Terrain node’u taşınabilir; rotation kimlik, scale `Vector3.ONE` kalmalıdır.

## Senkronizasyon maliyeti

Height ve paint tarafında yalnızca dirty region rectangle yeniden örneklenir. Değişiklikler kare içinde birleştirilip her sistem için en fazla tek makro texture upload yapılır. Makro texture çözünürlüğü 257² veya 513² ile sınırlıdır. Collision rebuild işlemleri ayrıca kuyruklanır.

## Test

```bash
godot --headless --path . --editor --quit-after 3
godot --headless --path . --script addons/island_terrain/test/foundation_test.gd
godot --headless --path . --script addons/island_terrain/test/sculpt_pipeline_test.gd
godot --headless --path . --script addons/island_terrain/test/collision_streaming_test.gd -- --case=shape
godot --headless --path . --script addons/island_terrain/test/collision_streaming_test.gd -- --case=movement
godot --headless --path . --script addons/island_terrain/test/collision_streaming_test.gd -- --case=dirty
godot --headless --path . --script addons/island_terrain/test/generation_graph_test.gd
godot --headless --path . --script addons/island_terrain/test/generation_controller_test.gd
godot --headless --path . --script addons/island_terrain/test/generation_facade_test.gd
godot --headless --path . --script addons/island_terrain/test/material_system_test.gd
godot --headless --path . --script addons/island_terrain/test/material_facade_test.gd
godot --headless --path . --script addons/island_terrain/test/material_paint_pipeline_test.gd
```

## Mimari sınırlar

- Renderer dosya sistemine erişmez.
- Persistence sahne node’u veya render RID’i yönetmez.
- Tüm dünya/region dönüşümleri tek koordinat servisi üzerinden geçer.
- EditorPlugin yalnızca orchestration yapar; stroke state ayrı session sınıflarındadır.
- Collision servisi edit veya persistence katmanına doğrudan bağımlı değildir.
- Generation controller yalnızca job yaşam döngüsünü yönetir.
- Material runtime shader backend’i ve metadata builder’ı izole eder.
- Paint servisi shader veya render RID’i yönetmez.
- Smooth dışındaki sculpt araçları full region snapshot oluşturmaz.
- Kazma sistemi heightfield koduna bağlanmaz; deformation interface üzerinden eklenir.
