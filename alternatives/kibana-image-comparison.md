# Kibana ve Dashboard Alternatifleri

| Aday | Backend uyumu | Legacy chart uyumu | Değerlendirme |
|---|---|---|---|
| Bitnami Kibana | Elasticsearch | Doğal | Mevcut bağımlılık; kaldırıldı |
| Elastic official Kibana | Aynı minor/patch Elastic Stack | Düşük | ECK ile seçildi |
| OpenSearch Dashboards | OpenSearch | Yok | Elasticsearch/Kibana hedefinden ürün migrasyonuna dönüşür |

Kibana resmi image'ı doğrudan eski Bitnami sub-chart'a yerleştirilmemiştir. ECK `Kibana` CR'ı kullanılarak bağlantı, TLS ve sürüm ilişkisi declarative hale getirilmiştir.
