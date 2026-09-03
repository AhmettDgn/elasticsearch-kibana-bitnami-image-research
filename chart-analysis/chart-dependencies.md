# Chart Dependency Analizi

## İncelenen yapı

- Elasticsearch chart: `18.1.8`, appVersion `8.2.0`.
- Kibana dependency: Bitnami Kibana `10.1.4`.
- Üst chart common dependency: Bitnami Common `1.14.1`.
- Kibana altında ikinci bir gömülü Bitnami Common `1.14.1` kopyası bulunuyor.
- `global.kibanaEnabled: true` olduğu için Kibana sub-chart aktiftir.

`Chart.yaml`, `Chart.lock`, paketlenmiş `charts/kibana` ve iki `common` library kopyası legacy dizininde korunmuştur.

## Sonuç

Bağımlılık yalnız container registry düzeyinde değildir. Template isimlendirme, capability seçimi, image oluşturma, pull secret, affinity ve validation fonksiyonları `common.*` helper'larına bağlıdır. Bu nedenle sadece registry/repository override edilmesi chart bağımlılığını ortadan kaldırmaz.

Aktif çözümde dış chart dependency bulunmaz. ECK operator ayrıca sabit sürümlü resmi Elastic Helm repository'sinden kurulur; uygulama chart'ı yalnız ECK CR'larını ve exporter kaynaklarını üretir.
