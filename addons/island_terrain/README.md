# IslandTerrain 0.5

Godot 4.6.3 Mobile Renderer için 4 km hayatta kalma adası terrain editörü.

## Çekirdek

- 4 km dünya ve 256 m region düzeni
- 257×257 region height verisi
- Sparse height, material, biome, wetness, hole ve foliage kanalları
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

## Allocation preflight

Generation başlamadan önce mevcut resident terrain belleği ile generation ve material metadata peak çalışma belleği birlikte tahmin edilir. Tahmin, cihaz profilindeki güvenli RAM zarfını aşarsa büyük `PackedArray` dizileri ayrılmadan işlem `ERR_OUT_OF_MEMORY` ile reddedilir.

Düşük, dengeli ve yüksek profiller ayrı terrain RAM/VRAM bütçelerine ve safety ratio değerlerine sahiptir. Bu değerler Inspector’dan görülebilir; telefonlarda `Balanced` dışına profiler sonucu olmadan çıkılmamalıdır.

## Biyom material sistemi

`IslandTerrainMaterialRuntime`, generation metadata’sını RGBA8 texture’a kare bütçeli biçimde encode eder:

- R: biyom kimliği
- G: nem
- B: nehir maskesi
- A: log-normalize flow accumulation

Varsayılan backend `Atlas`tır. `Texture2DArray` atanırsa aynı shader array backend’ini kullanabilir; array eksikse otomatik olarak atlas veya color-only fallback’e geçilir.

Altı temel katman bulunur: Sand, Grass, Forest, Wetland, Rock ve Mountain. Her katmanda tint, atlas slotu, metre başına döşeme ölçeği, roughness ve metallic ayarlanabilir. Kullanıcı atlas vermemişse deterministic nötr fallback atlas üretilir.

Yakın LOD’lar atlas veya texture array örnekler. `detail_lod_limit` üzerindeki uzak LOD’lar yalnızca katman tint’i kullanır. Metadata yeniden üretilirken eski texture shader’dan kaldırılır.

Public API:

- `refresh_material_library()`
- `get_effective_material_backend()`
- `get_material_metadata_texture()`
- `get_material_override_texture()`
- `is_material_metadata_building()`
- `get_material_working_memory_bytes()`
- `get_material_resident_memory_bytes()`

## Region biyom ve material paint

Manuel paint, prosedürel generation metadata’sını değiştirmez. Yüksek çözünürlüklü override değerleri region dosyalarında tutulur; renderer yalnızca cihaz profiliyle sınırlandırılmış küçük bir RGBA8 override texture kullanır:

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

Kullanılmayan region’larda paint dizileri tahsis edilmez. İlk gerçek paint işleminde yalnız gerekli ID ve blend maskeleri açılır. 257×257 bir region için tam biyom + material override yaklaşık 264 KB kullanır ve canlı region RAM muhasebesine anında eklenir.

Bir stroke bütün region’ı veya dünyayı kopyalamaz. Yalnızca değişen `Rect2i` içindeki önce/sonra byte dizileri tutulur ve varsayılan stroke undo sınırı 8 MB’dir. Sınır aşılırsa son dab geri sarılır. Biyom ve material transaction’ları kanal-seçimlidir; bir biyom undo işlemi material kanalını değiştirmez.

Read-only biyom/material sorguları boş region oluşturmaz. Önce cache, sonra yalnız gerçekten mevcut kaynak/runtime region dosyaları kontrol edilir.

Public API:

- `apply_paint_command()`
- `apply_paint_transaction_before()`
- `apply_paint_transaction_after()`
- `get_biome_override_at_world()`
- `get_material_override_at_world()`
- `flush_material_override_sync()`

## Runtime sağlık koruması

`IslandTerrainRuntimeWatchdog`, private region veya renderer dizilerine erişmeden public metric API’leri ile Godot `Performance` monitörlerini birleştirir.

Ölçülen terrain verileri:

- Region cache byte/count ve dirty region sayısı
- Generation ve material geçici çalışma belleği
- Kalıcı paint override resident belleği
- Aktif/bekleyen clipmap LOD’ları
- Aktif/bekleyen collision patch’leri
- Runtime quality reduction seviyesi

Godot monitor’larından FPS, process/physics süresi, static memory, video/texture memory, draw call ve node sayısı alınır. Platformun vermediği monitor değerleri sıfır olabilir; terrain-owned RAM ana karar kaynağı olarak kalır.

`IslandTerrainHealthPolicy`, soft/hard/critical bellek oranlarını, düşük FPS eşiğini, ardışık kötü/iyi örnek sayılarını ve kalite değişim cooldown’ını içerir. Tek kötü örnek kaliteyi düşürmez. Auto-recovery varsayılan olarak kapalıdır.

Veri kaybısız kalite basamakları:

1. Full
2. Reduced Detail: yakın material detay LOD sınırı azaltılır
3. Reduced Shadows: terrain LOD gölgeleri kapatılır
4. Reduced Collision: collision yarıçapı düşürülür ve fazla pooled body serbest bırakılır

Hard/critical baskıda yalnızca temiz region cache ve fazla pooled collision body’leri bırakılır. Kirli region, sculpt/paint delta, generation sonucu ve kaydedilmiş terrain verisi silinmez.

Public API:

- `sample_health_now()`
- `get_last_health_snapshot()`
- `set_auto_quality_protection_enabled()`
- `get_runtime_quality_reduction()`
- `restore_runtime_quality()`

Policy izin verirse Godot Performance paneline `IslandTerrain/*` custom monitor’ları eklenir; watchdog tree’den çıkınca kaldırılır.

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

Editor kodu region dizilerine doğrudan erişmez. Undo/redo bütün dünya veya bütün region kopyası saklamaz; yalnızca etkilenen `Rect2i` içindeki height ve validity değerlerini tutar. Bir stroke için varsayılan undo belleği 8 MB ile sınırlıdır.

Prosedürel ada görüntüsü immutable base height olarak korunur. Düzenlenmemiş region örnekleri base yüzeyden okunur. Undo bir örneği düzenlenmemiş duruma döndürdüğünde görüntü prosedürel tabana geri döner.

Sculpt ve Paint modları karşılıklı dışlanır. İkisi de aynı `EditorUndoRedoManager` nesne geçmişini kullanır; işlemler tek kronolojik geri-al zincirinde kalır.

## Streamed collision

Tüm adaya tek fizik şekli oluşturulmaz. `IslandTerrainCollisionService`, oyuncu veya aktif kamera çevresinde pool’lanmış `StaticBody3D + HeightMapShape3D` patch’leri yönetir.

- Patch: 64 × 64 metre
- Örnek aralığı: 1 metre
- Balanced aktif yarıçap: 96 metre
- Kare başına en fazla bir patch build
- Sculpt, undo ve redo sonrası yalnızca kesişen aktif patch rebuild’i
- Profil veya height texture değişiminde stale patch temizliği
- Collision node’larında ölçek kullanılmaz

## Mobil profiller

| Profil | Makro height/metadata/paint | LOD | Base quads | Cache | Shadow LOD | Collision yarıçapı | CPU bütçesi |
|---|---:|---:|---:|---:|---:|---:|---:|
| Low | 257² | 5 | 48 | 5 | 1 | 64 m | 1 ms |
| Balanced | 257² | 6 | 64 | 9 | 2 | 96 m | 2 ms |
| High | 513² | 7 | 80 | 25 | 4 | 160 m | 3 ms |
| Editor Preview | 513² | 7 | 64 | 9 | 2 | 96 m | 2 ms |

Telefonlarda varsayılan profil `Balanced`, material backend `Atlas` ve runtime kalite koruması açık olmalıdır. `High` ve `Texture Array` yalnızca cihaz profiler sonucu uygunsa kullanılmalıdır. Büyük 4097² runtime heightmap veya paint texture oluşturulmaz.

## Kullanım

1. **Project > Project Settings > Plugins** bölümünden `IslandTerrain` eklentisini etkinleştir.
2. 3D sahneye `IslandTerrain3D` node’u ekle.
3. Renderer ayarını `Mobile` olarak bırak.
4. `generation_profile` ayarlarını düzenle.
5. `material_library` içinde backend, katmanlar ve `detail_lod_limit` değerini ayarla.
6. `health_policy` içinde FPS, RAM/VRAM ve cooldown eşiklerini ayarla.
7. Terrain node’unu seç.
8. Sol üst dock’tan Sculpt, sol alt dock’tan Paint modunu aç.
9. Tek parmak veya sol tık ile düzenle; ikinci parmak kamera kontrolüne ayrılır.
10. Runtime collision için `collision_target_path` alanını oyuncuya bağla.

Terrain node’u taşınabilir; rotation kimlik, scale `Vector3.ONE` kalmalıdır.

## Senkronizasyon maliyeti

Height ve paint tarafında yalnızca dirty region rectangle yeniden örneklenir. Değişiklikler kare içinde birleştirilip her sistem için en fazla tek makro texture upload yapılır. Makro texture çözünürlüğü 257² veya 513² ile sınırlıdır. Collision rebuild işlemleri ayrıca kuyruklanır.

Biyom metadata ve manuel override texture’ları RGBA8’dir. Metadata builder completion sonrasında geçici source/result referanslarını ve byte buffer’ı bırakır. Paint override backing image kalıcı resident bellek olarak ayrı raporlanır.

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
godot --headless --path . --script addons/island_terrain/test/material_paint_facade_test.gd
godot --headless --path . --script addons/island_terrain/test/production_hardening_test.gd
godot --headless --path . --script addons/island_terrain/test/long_session_stress_test.gd
godot --headless --path . --script addons/island_terrain/test/hardening_facade_test.gd
```

## Mimari sınırlar

- Renderer dosya sistemine erişmez.
- Persistence sahne node’u veya render RID’i yönetmez.
- Tüm dünya/region dönüşümleri tek koordinat servisi üzerinden geçer.
- EditorPlugin yalnızca orchestration yapar; sculpt ve paint stroke state ayrı session sınıflarındadır.
- Collision servisi edit veya persistence katmanına doğrudan bağımlı değildir.
- Generation controller yalnızca job yaşam döngüsünü ve allocation preflight’i yönetir.
- Material runtime shader backend’i ve metadata builder’ı izole eder.
- Paint servisi shader, render RID’i veya collision body yönetmez.
- Runtime watchdog karar üretir; quality controller yalnızca geri döndürülebilir servis ayarlarını uygular.
- Smooth dışındaki sculpt araçları full region snapshot oluşturmaz.
- Kazma sistemi heightfield koduna bağlanmaz; deformation interface üzerinden eklenir.
