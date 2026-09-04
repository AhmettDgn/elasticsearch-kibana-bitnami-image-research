# Seçilen Yaklaşım

## Karar

Aktif deployment, ECK `3.5.0` üzerinde Elasticsearch ve Kibana `8.19.21` CR'ları ile kurulmuştur. Metrics için Prometheus Community exporter `1.11.0` ayrı Deployment olarak çalışmaktadır.

## Neden image override değil?

Image override sadece image adresini değiştirir; Bitnami entrypoint, healthcheck, environment değişkeni, config/data mount yolu ve common helper sözleşmelerini değiştirmez. Bu nedenle render başarısı runtime uyumu anlamına gelmez.

## Neden ECK?

- Resmi Elasticsearch ve Kibana yaşam döngüsü yönetimi.
- Varsayılan TLS ve authentication.
- Elasticsearch/Kibana ilişkisinin `elasticsearchRef` ile yönetilmesi.
- Tek `stack.version` ile sürüm drift'inin önlenmesi.
- Bitnami common/sub-chart/helper katmanlarının tamamen kaldırılması.
- Gelecekte node sayısı, storage ve upgrade stratejisinin declarative yönetilebilmesi.

Bu topoloji yalnız tek VPS lab testidir; production HA iddiası yoktur.

## Gerçek ortam doğrulaması

Yaklaşım 2026-09-04 tarihinde Ubuntu 24.04.4 LTS/amd64, tek node K3s `v1.36.4+k3s1` Contabo ortamında doğrulandı. TLS/authentication, green cluster health, index/document/search, Kibana status, exporter metrics, tekrarlı Helm upgrade ve pod recreation sonrası PVC persistence testleri başarılı oldu. Ayrıntılar [`tests/integration/contabo-validation-2026-09-04.md`](../tests/integration/contabo-validation-2026-09-04.md) dosyasındadır.
