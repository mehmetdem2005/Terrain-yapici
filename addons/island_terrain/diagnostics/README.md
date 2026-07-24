# Runtime Health Protection

IslandTerrain 0.5, telefonlarda uzun oturum sırasında terrain kaynaklı bellek ve render baskısını ölçer. Watchdog private region veya renderer dizilerine erişmez; servislerin public metric API’lerini ve Godot `Performance` monitörlerini kullanır.

## Ölçülen değerler

- FPS, process ve physics süresi
- Debug build’de static memory
- Video ve texture memory
- Draw call ve node sayısı
- Region cache byte/count ve dirty region sayısı
- Generation/material geçici çalışma belleği
- Aktif/bekleyen clipmap LOD’ları
- Aktif/bekleyen collision patch’leri
- Runtime quality reduction seviyesi

`IslandTerrain3D.sample_health_now()` anlık snapshot üretir. `get_last_health_snapshot()` kopya döndürür; dış kod watchdog state’ini değiştiremez.

## Baskı ve hysteresis

`IslandTerrainHealthPolicy` soft, hard ve critical RAM/VRAM eşiklerini; düşük FPS eşiğini; ardışık kötü/iyi örnek sayılarını ve kalite değişim cooldown’ını içerir.

Tek düşük FPS örneği kaliteyi değiştirmez. Otomatik recovery varsayılan olarak kapalıdır; telefonlarda quality oscillation önlenir. Critical terrain RAM baskısı temiz cache bırakmayı hemen ister fakat kirli region’ları silmez.

## Kalite basamakları

1. Full
2. Reduced Detail: material detay LOD sınırı azalır
3. Reduced Shadows: terrain LOD gölgeleri kapanır
4. Reduced Collision: collision yarıçapı 64 metreye/patche düşer ve fazla pooled body serbest bırakılır

Bu basamaklar generation sonucunu, sculpt verisini veya region kayıtlarını değiştirmez. `restore_runtime_quality()` baseline değerlerine döner.

## Allocation preflight

Generation başlamadan result kanalları, erosion/flow çalışma dizileri, metadata staging ve mevcut resident terrain belleği tahmin edilir. Güvenli RAM zarfı aşılırsa büyük packed diziler ayrılmadan `ERR_OUT_OF_MEMORY` döner.

## Custom Performance monitor’ları

Policy izin verirse şu monitor’lar eklenir:

- `IslandTerrain/Region Cache MB`
- `IslandTerrain/Generation Working MB`
- `IslandTerrain/Material Working MB`
- `IslandTerrain/Collision Patches`
- `IslandTerrain/Pressure Level`
- `IslandTerrain/Runtime Quality Reduction`

Watchdog tree’den çıktığında monitor’ları kaldırır.
