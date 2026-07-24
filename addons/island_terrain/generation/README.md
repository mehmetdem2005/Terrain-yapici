# Island Generation Graph

Kare bütçeli deterministic üretim aşamaları:

1. Kıyı ve ana yükselti
2. Termal erozyon
3. Akış yönü ve birikimi
4. Nehir oyma
5. Nem ve biyom sınıflandırması

`IslandTerrainGenerationJob.process_budget()` her çağrıda sınırlı CPU süresi kullanır. Üretim sonucu height, moisture, river mask, flow accumulation ve biome kanallarını taşır.
