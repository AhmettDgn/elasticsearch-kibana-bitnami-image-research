# Kibana Sub-chart Analizi

Legacy Kibana `10.1.4` chart'ı kendi Bitnami Common `1.14.1` dependency'sini taşır. Deployment; Bitnami environment değişkenlerini, `/bitnami/kibana` persistence yolunu, `/opt/bitnami/kibana/config` sertifika/config yollarını ve Bitnami başlangıç scriptlerini varsayar.

Üst values Elasticsearch'i `8.2.0`, Kibana'yı `8.17.2` olarak ayarlamıştır. Elastic Stack bileşenlerinin farklı minor sürümlerde tutulması güvenilir bir hedef değildir.

Aktif çözümde Kibana sub-chart yoktur. `Kibana` ECK CR'ı Elasticsearch'e `elasticsearchRef` ile bağlanır; TLS, kullanıcı bağlantısı ve sertifikalar operator tarafından yönetilir. Elasticsearch ve Kibana aynı `stack.version` değerini kullanır.
