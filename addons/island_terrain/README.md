# IslandTerrain 0.3

Godot 4.6.3 Mobile Renderer için 4 km hayatta kalma adası terrain editörü.

## Çekirdek

- 4 km dünya ve 256 m region düzeni
- 257×257 region height verisi
- Sparse height validity, material, biome, wetness, hole ve foliage kanalları
- Canlı RAM muhasebesi ve temiz-region LRU tahliyesi
- Kirli region veri koruması
- `res://` kaynak ve `user://` runtime copy-on-write depolama
- Geçici dosya, birleşik checksum, yedek ve terfi kullanan atomik kayıt
- Region format v1 → v2 otomatik migration
- Geometry clipmap merkez grid’i, içi boş LOD halkaları ve dış etekler
- Kare başına en fazla bir LOD oluşturma
- Tek ShaderMaterial ve instance LOD uniform’ları
- Satır bazlı, kare bütçeli ada önizleme üretimi
- Gelecekteki sparse voxel/SDF kazma backend sözleşmesi

## Sculpt sistemi

Araçlar:

- Yükselt
- Alçalt
- Yumuşat
- Düzleştir

Her fırça darbesi şu üretim zincirinden geçer:

```text
Editor Input
  → TerrainSculptSession
  → TerrainSculptCommand
  → TerrainEditService
  → TerrainRegionRepository
  → MacroHeightSync
```

Editor kodu region dizilerine doğrudan erişmez. Undo/redo bütün dünya veya bütün region kopyası saklamaz; yalnızca etkilenen `Rect2i` içindeki height ve validity değerlerini tutar. Bir stroke için varsayılan undo belleği 8 MB ile sınırlıdır.

Prosedürel ada görüntüsü immutable base height olarak korunur. Düzenlenmemiş region örnekleri sıfır yükseklik sayılmaz; base yüzeyden okunur. Undo bir örneği düzenlenmemiş duruma döndürdüğünde görüntü prosedürel tabana geri döner.

## Streamed collision

Tüm adaya tek fizik şekli oluşturulmaz. `IslandTerrainCollisionService`, oyuncu veya aktif kamera çevresinde pool’lanmış `StaticBody3D + HeightMapShape3D` patch’leri yönetir.

Varsayılan davranış:

- Patch: 64 × 64 metre
- Örnek aralığı: 1 metre
- Balanced aktif yarıçap: 96 metre
- Kare başına en fazla bir patch build
- Dairesel hedef kümesi; uzaktaki patch’ler kapatılıp pool’a alınır
- Sculpt, undo ve redo yalnızca kesişen aktif patch’leri rebuild kuyruğuna ekler
- Profil veya height texture değişiminde eski patch’ler pool’a çekilip yeniden kurulur
- Collision node’ları ölçeklenmez

Oyun sahnesinde `collision_target_path` alanına oyuncu `Node3D` yolunu ver. Boş bırakılırsa servis aktif 3D kamerayı takip eder. `collision_layer`, `collision_mask`, `collision_patch_size_m` ve `collision_update_interval_s` Inspector’dan ayarlanabilir.

## Mobil profiller

| Profil | Makro height | LOD | Base quads | Cache | Shadow LOD | Collision yarıçapı | CPU bütçesi |
|---|---:|---:|---:|---:|---:|---:|---:|
| Low | 257² | 5 | 48 | 5 | 1 | 64 m | 1 ms |
| Balanced | 257² | 6 | 64 | 9 | 2 | 96 m | 2 ms |
| High | 513² | 7 | 80 | 25 | 4 | 160 m | 3 ms |
| Editor Preview | 513² | 7 | 64 | 9 | 2 | 96 m | 2 ms |

Telefonlarda varsayılan profil `Balanced` olmalıdır. `High` yalnızca profiler sonucu uygunsa kullanılmalıdır.

## Kullanım

1. Godot’ta **Project > Project Settings > Plugins** bölümünden `IslandTerrain` eklentisini etkinleştir.
2. 3D sahneye `IslandTerrain3D` node’u ekle.
3. Renderer ayarını `Mobile` olarak bırak.
4. Terrain node’unu seç.
5. Sol dock’taki `IslandTerrain Sculpt` panelinden Sculpt Modu’nu aç.
6. Tek parmak veya sol tık ile düzenle; ikinci parmak kamera kontrolüne ayrılır.
7. Paneldeki Geri Al/Yinele düğmeleri Godot sahne undo geçmişini kullanır.
8. Runtime collision için `collision_target_path` alanını oyuncuya bağla.

Terrain node’u taşınabilir; rotation kimlik, scale `Vector3.ONE` kalmalıdır.

## Senkronizasyon maliyeti

CPU tarafında yalnızca dirty region rectangle yeniden örneklenir. Godot’un public `ImageTexture.update()` API’si texture görüntüsünü bütün olarak güncellediğinden, değişiklikler kare içinde birleştirilip en fazla tek makro texture upload yapılır. Runtime makro texture 257² veya 513² ile sınırlandırılmıştır.

Collision rebuild işlemleri de kuyruklanır. Normal çalışmada tek karede birden fazla patch yeniden oluşturulmaz; hızlı hareket sırasında önce yakın patch’ler aktif edilir, eski gövdeler aynı refresh içinde pool’dan tekrar kullanılır.

## Test

```bash
godot --headless --path . --editor --quit-after 3
godot --headless --path . --script addons/island_terrain/test/foundation_test.gd
godot --headless --path . --script addons/island_terrain/test/sculpt_pipeline_test.gd
godot --headless --path . --script addons/island_terrain/test/collision_streaming_test.gd -- --case=shape
godot --headless --path . --script addons/island_terrain/test/collision_streaming_test.gd -- --case=movement
godot --headless --path . --script addons/island_terrain/test/collision_streaming_test.gd -- --case=dirty
```

## Mimari sınırlar

- Renderer dosya sistemine erişmez.
- Persistence sahne node’u veya render RID’i yönetmez.
- Tüm dünya/region dönüşümleri tek koordinat servisi üzerinden geçer.
- EditorPlugin yalnızca orchestration yapar; stroke state ayrı session sınıfındadır.
- Collision servisi edit veya persistence katmanına doğrudan bağımlı değildir; yalnızca typed transaction/rect bildirimi alır.
- Smooth dışındaki araçlar full region snapshot oluşturmaz.
- Büyük 4097² runtime heightmap oluşturulmaz.
- Kazma sistemi heightfield koduna bağlanmaz; deformation interface üzerinden eklenir.
