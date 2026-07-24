# IslandTerrain Foliage Streaming

Bu modül, bütün adaya sahne node'u veya önceden üretilmiş transform listesi dağıtmadan kamera/oyuncu çevresindeki bitki örtüsünü yönetir.

## Veri akışı

```text
World seed + cell coordinate + layer index
  → TerrainFoliagePlanner
  → compact TerrainFoliageCellPlan
  → TerrainFoliageCellRuntime
  → layer başına MultiMeshInstance3D
```

## Mobil sınırlar

- Varsayılan hücre: 32 × 32 metre
- Varsayılan aktif yarıçap: 96 metre
- Hücre build: kare başına en fazla 1
- Build CPU bütçesi: varsayılan 0,75 ms
- Aktif hücre hard cap: 64
- Pool hard cap: 32
- Instance başına Node3D yoktur
- Gölge ve GI varsayılan olarak kapalıdır
- Hücre planları unload sırasında bırakılabilir; seed tabanlı yeniden üretim deterministiktir

## Layer filtreleri

Her layer şu kuralları bağımsız uygular:

- Allowed biome listesi
- Min/max elevation
- Max slope
- Min/max moisture
- Foliage mask
- Hücre başına density ve instance hard cap
- Min/max scale, random yaw ve normal alignment

Mesh atanmayan layer planlamaya katılabilir ancak render instance üretmez. Mesh kaynakları hücreler arasında paylaşılır; yalnız MultiMesh transform buffer'ları hücreye özeldir.

## Runtime davranışı

`TerrainFoliageStreamer`, hedef hareketini periyodik ölçer, dairesel aktif hücre kümesini mesafeye göre sıralar ve `max_active_cells` sınırında keser. Çıkan hücreler pool'a döner. Pool sınırı aşılırsa fazla runtime node ve MultiMesh buffer'ları serbest bırakılır.

Biyom/material paint veya foliage mask değişiklikleri `invalidate_cell()` ya da `invalidate_world_circle()` üzerinden yalnız kesişen aktif hücreleri yeniden kuyruğa alır.
