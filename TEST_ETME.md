# IslandTerrain telefon testi ve editör kullanımı

Bu paket Godot **4.6.3** ve **Mobile Renderer** için hazırlanmıştır.

## Telefonda açma

1. Eski test klasörünü kullanma; yeni ZIP'i ayrı bir klasöre çıkar.
2. Godot Android editörünü aç.
3. **İçe Aktar / Import** seçeneğine bas.
4. Çıkardığın klasördeki `project.godot` dosyasını seç.
5. Projeyi aç.

## Çalışan demoyu deneme

Sağ üstteki **Çalıştır** düğmesine bas. Runtime demo açılır.

- Ekranı sürükle: kamerayı ada etrafında döndürür.
- `+ Yakın`: kamerayı yaklaştırır.
- `− Uzak`: kamerayı uzaklaştırır.
- `Sıfırla`: başlangıç kamera açısına döner.
- `Clipmap Testi`: gerçek terrain renderer'ını ayrı olarak sınar.

## Terrain şekillendirme araçlarını açma

Araçlar oyun çalışırken görünmez; Godot'un **editör ekranında** kullanılır.

1. Çalışan oyunu durdur ve 3D editöre dön.
2. Alttaki **Dosya Sistemi / FileSystem** bölümünden `editor/terrain_editor_demo.tscn` sahnesini aç.
3. Sol sahne ağacında en üstteki **IslandTerrain3D** node'una dokunup seç.
4. Editörün alt çubuğunda **IslandTerrain** düğmesi otomatik açılır. Görünmüyorsa alt çubuğu yatay kaydır.
5. Panelde iki sekme vardır:
   - **Şekillendir**: arazi yüksekliğini değiştirir.
   - **Boya**: biyom ve zemin malzemesi override'ı uygular.

## Şekillendir sekmesi

1. **Sculpt Modu** anahtarını aç.
2. Araç seç:
   - **Yükselt**: zemini yukarı çıkarır.
   - **Alçalt**: zemini aşağı indirir.
   - **Yumuşat**: keskin yükseklik farklarını azaltır.
   - **Düzleştir**: ilk dokunduğun yüksekliğe doğru düzleştirir.
3. **Yarıçap**, **Güç**, **Falloff** ve **Stroke Aralığı** değerlerini ayarla.
4. 3D görünümde terrain üzerine tek parmakla dokunup sürükle.
5. Kamera hareketi için Sculpt Modu'nu geçici kapat veya iki parmak kullan.
6. Paneldeki **Geri Al / Yinele** düğmeleri stroke geçmişini yönetir.

## Boya sekmesi

1. **Paint Modu** anahtarını aç.
2. **Biyom Boya**, **Malzeme Boya** veya geri yükleme araçlarından birini seç.
3. Biyom ya da malzeme türünü belirle.
4. Terrain üzerinde tek parmakla dokunup sürükle.

Sculpt ve Paint aynı anda açık kalmaz; biri açıldığında diğeri otomatik kapanır.

## Panel görünmüyorsa

- **Proje > Proje Ayarları > Eklentiler** bölümünde `IslandTerrain` durumunun **Etkin** olduğunu doğrula.
- Sahne ağacında sıradan `Node3D` değil, scripti `IslandTerrain3D` olan kök node'u seç.
- Telefon editöründe alt panel kapalıysa ekranın altındaki panel başlıklarını yana kaydır ve **IslandTerrain** başlığına bas.

## Hata bildirirken

Godot alt panelindeki ilk kırmızı hata satırını ve cihaz modelini gönder. Arazi görünmüyorsa ayrıca üstte `3D` görünümünün seçili olduğunu doğrula.
