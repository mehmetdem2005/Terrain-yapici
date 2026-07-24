# Terrain-yapici

Godot 4.6.3 Mobile Renderer için büyük, bölgesel ve gelecekte kazılabilir terrain eklentisi.

## IslandTerrain 0.4

- 4 km region-streamed terrain foundation
- Geometry clipmap LOD renderer
- Mobil RAM/VRAM ve kare başına iş bütçeleri
- Atomik region kaydı ve runtime copy-on-write
- Yükselt, alçalt, yumuşat ve düzleştir sculpt araçları
- Sparse procedural-base koruması
- Dirty-rectangle CPU senkronizasyonu ve coalesced macro texture upload
- Delta tabanlı bounded undo/redo
- Fare ve Android editör için tek parmak sculpt paneli
- Hedef/kamera çevresinde pool’lanmış streamed collision patch’leri
- Sculpt, undo ve redo sonrası sınırlı collision rebuild kuyruğu
- Kare bütçeli kıyı, yükselti, termal erozyon, akış, nehir ve biyom generation graph’ı
- Height, moisture, biome, river mask ve flow accumulation dünya sorguları
- Atlas-first biyom material sistemi ve opsiyonel `Texture2DArray` backend’i
- Yakın LOD detay örneklemesi, uzak LOD tint-only maliyet azaltma
- Kare bütçeli RGBA8 biyom/nem/nehir/akış metadata texture üretimi
- Gelecekteki sparse voxel/SDF kazma backend sözleşmesi

## Kullanım

1. Projeyi Godot 4.6.3 ile aç.
2. `Project > Project Settings > Plugins` bölümünden `IslandTerrain` eklentisini etkinleştir.
3. 3D sahneye `IslandTerrain3D` ekle.
4. `generation_profile` üzerinden kıyı, erozyon, nehir ve biyom parametrelerini ayarla.
5. `material_library` üzerinden atlas, katman renkleri, döşeme ölçekleri ve yakın LOD sınırını ayarla.
6. Node’u seçince sol dock’taki `IslandTerrain Sculpt` panelini kullan.
7. Oyun sahnesinde `collision_target_path` alanına oyuncu node’unu ver; boş bırakılırsa aktif kamera kullanılır.
8. Telefonlarda `Balanced` profil ve `Atlas` backend ile başla.

Ayrıntılı mimari ve test bilgileri `addons/island_terrain/README.md` dosyasındadır.
