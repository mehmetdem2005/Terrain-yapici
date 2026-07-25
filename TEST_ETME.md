# IslandTerrain telefon testi

Bu paket Godot **4.6.3** ve **Mobile Renderer** için hazırlanmıştır.

## Telefonda açma

1. ZIP dosyasını çıkar.
2. Godot Android editörünü aç.
3. **İçe Aktar / Import** seçeneğine bas.
4. Çıkardığın klasördeki `project.godot` dosyasını seç.
5. Projeyi açıp sağ üstteki **Çalıştır** düğmesine bas.

## Demo kontrolleri

- Ekranı sürükle: kamerayı ada etrafında döndürür.
- `+ Yakın`: kamerayı yaklaştırır.
- `− Uzak`: kamerayı uzaklaştırır.
- `Sıfırla`: başlangıç kamera açısına döner.

İlk açılışta ada; kıyı, yükseklik, erozyon, nehir, nem, biyom ve material metadata aşamalarından geçerek üretilir. Durum paneli güncel aşamayı gösterir.

## Editörü deneme

3D sahnedeki `IslandTerrain3D` node'unu seçtiğinde eklentinin Sculpt ve Paint araçlarını kullanabilirsin. Telefon için varsayılan profil `Balanced` olarak bırakılmıştır.

## Hata bildirirken

Godot alt panelindeki ilk kırmızı hata satırını ve cihaz modelini gönder. FPS düşüşü varsa yaklaşık kaç saniye sonra başladığını da belirt.
