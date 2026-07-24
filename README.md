# Terrain-yapici

Godot 4.6.3 Mobile Renderer için büyük, bölgesel ve gelecekte kazılabilir terrain eklentisi.

## IslandTerrain 0.5

- 4 km region-streamed terrain foundation
- Geometry clipmap LOD renderer
- Mobil RAM/VRAM ve kare başına iş bütçeleri
- Generation başlamadan allocation preflight
- Runtime health snapshot ve custom Godot Performance monitor’ları
- Hysteresis/cooldown tabanlı otomatik kalite koruması
- Veri kaybısız material-detail, shadow ve collision-radius düşürme basamakları
- Kritik baskıda clean region cache ve pooled collision memory bırakma
- Atomik region kaydı ve runtime copy-on-write
- Yükselt, alçalt, yumuşat ve düzleştir sculpt araçları
- Sparse procedural-base koruması
- Dirty-rectangle CPU senkronizasyonu ve coalesced macro texture upload
- Delta tabanlı bounded undo/redo
- Fare ve Android editör için tek parmak sculpt paneli
- Hedef/kamera çevresinde pool’lanmış streamed collision patch’leri
- Kare bütçeli kıyı, yükselti, termal erozyon, akış, nehir ve biyom generation graph’ı
- Height, moisture, biome, river mask ve flow accumulation dünya sorguları
- Atlas-first biyom material sistemi ve opsiyonel `Texture2DArray` backend’i
- Yakın LOD detay örneklemesi, uzak LOD tint-only maliyet azaltma
- Gelecekteki sparse voxel/SDF kazma backend sözleşmesi

## Kullanım

1. Projeyi Godot 4.6.3 ile aç.
2. `Project > Project Settings > Plugins` bölümünden `IslandTerrain` eklentisini etkinleştir.
3. 3D sahneye `IslandTerrain3D` ekle.
4. `generation_profile` üzerinden kıyı, erozyon, nehir ve biyom parametrelerini ayarla.
5. `material_library` üzerinden atlas ve yakın LOD sınırını ayarla.
6. `health_policy` üzerinden FPS/bellek eşikleri ve cooldown değerini ayarla.
7. Node’u seçince sol dock’taki `IslandTerrain Sculpt` panelini kullan.
8. Oyun sahnesinde `collision_target_path` alanına oyuncu node’unu ver.
9. Telefonlarda `Balanced`, `Atlas` ve açık runtime kalite korumasıyla başla.

Ayrıntılı mimari ve test bilgileri `addons/island_terrain/README.md` dosyasındadır.
