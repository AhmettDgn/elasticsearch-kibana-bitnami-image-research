# Ekran Görüntüsü Kanıt Raporu

Bu dizin, 2026-09-04 tarihli gerçek Contabo K3s doğrulamasından seçilen teknik kanıtları içerir. Görüntüler credential, Secret data, token, SSH anahtarı veya gerçek parola içermez.

## Kanıt matrisi

| Dosya | Kanıtlanan durum | Teknik yorum |
|---|---|---|
| [`01-stack-pods-running.png`](01-stack-pods-running.png) | Elasticsearch, Kibana ve exporter pod'larının tamamı `1/1 Running` | Aktif stack'in workload seviyesinde çalıştığını ve exporter CreateContainerConfigError sorununun çözüldüğünü gösterir. |
| [`02-eck-resources-green.png`](02-eck-resources-green.png) | Elasticsearch ve Kibana `8.19.21`, health `green`; Elasticsearch phase `Ready` | ECK custom resource reconcile sürecinin başarıyla tamamlandığını ve sürüm drift'i olmadığını kanıtlar. |
| [`03-pvc-bound-20gi.png`](03-pvc-bound-20gi.png) | Elasticsearch PVC `20Gi`, `Bound`, `RWO`, `local-path` | İstenen persistent storage kaynağının provision edildiğini gösterir; node/disk arızasına karşı HA anlamına gelmez. |
| [`04-elasticsearch-cluster-health-green.png`](04-elasticsearch-cluster-health-green.png) | Cluster `green`, 1 node, 39 active shard, 0 unassigned shard, `%100` active shard | ECK CA, SAN hostname ve authentication ile yapılan gerçek `/_cluster/health` çağrısının başarılı sonucudur. |
| [`05-exporter-elasticsearch-metrics.png`](05-exporter-elasticsearch-metrics.png) | Exporter `/metrics` üzerinde cluster health metrikleri | Exporter'ın yalnız ayakta olmadığını, Elasticsearch'e authenticated bağlanıp gerçek metrik ürettiğini kanıtlar. |
| [`06-demo-index-green.png`](06-demo-index-green.png) | `demo-index` health `green`, primary 1, replica 0, document count 1 | Tek node topolojisine uygun replica ayarını ve index/document varlığını gösterir. |
| [`07-demo-index-search-result.png`](07-demo-index-search-result.png) | `demo-index` search sonucu 1 hit ve `_id=1` | Indexlenen test dokümanının Elasticsearch tarafından geri okunabildiğini kanıtlar. |
| [`08-kibana-status-available.png`](08-kibana-status-available.png) | Kibana `/api/status` sonucu `overall.level=available` | UI görüntüsü olmadan Kibana backend servisinin TLS üzerinden kullanılabilir olduğunu doğrular. |
| [`09-persistence-after-recreation.png`](09-persistence-after-recreation.png) | Pod recreation öncesi/sonrası document `found=true`; ECK tekrar `Ready/green` | Yeni pod discovery/readiness yarışının çözüldüğünü ve `local-path` PVC verisinin pod recreation boyunca korunduğunu kanıtlar. |
| [`10-static-regression-tests-passed.png`](10-static-regression-tests-passed.png) | Helm lint, beş regression grubu, kubeconform ve static testler başarılı | Chart render ve otomasyonun bilinen race/TLS/evidence/SIGPIPE senaryolarına karşı doğrulandığını gösterir. |

## Seçim ve güvenlik notları

- Orijinal node/StorageClass ekran görüntüsünde açık sunucu IP adresi bulunduğundan public repository'ye alınmadı. Ortam bilgileri sanitize edilmiş [`Contabo validasyon raporunda`](../tests/integration/contabo-validation-2026-09-04.md) yer alır.
- Service listesi ekran görüntüsü Kubernetes iç ağ IP'lerini içerdiğinden public repository'ye alınmadı. Servis tiplerinin ClusterIP olduğu sanitize edilmiş validasyon raporu ve server-local `services.txt` kanıtında kayıtlıdır.
- Aynı içeriğe sahip ikinci exporter metrics görüntüsü hash karşılaştırmasıyla tekrar olarak tespit edildi ve eklenmedi.
- İki Kibana status görüntüsünden daha okunaklı olan seçildi; yinelenen görüntü eklenmedi.
- Windows üzerinden Kibana UI ekran görüntüsü erişim/sertifika kısıtı nedeniyle güvenilir şekilde alınamadı. Bu durum deployment hatası olarak değerlendirilmedi; ECK resource health `green` ve `/api/status` sonucu `available` ile backend kullanılabilirliği doğrulandı.
- Görsellerde kullanılan `ELASTIC_PASSWORD` yalnız shell variable adıdır; gerçek parola değeri görüntülenmemektedir.

## Sınır

Bu kanıtlar tek node lab ortamına aittir. `local-path` persistence, pod recreation karşısında doğrulanmıştır; fiziksel VPS veya disk kaybına karşı yedeklilik sağlamaz.
