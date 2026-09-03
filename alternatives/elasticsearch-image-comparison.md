# Elasticsearch Alternatifleri

| Aday | Lisans/yönetim | Multiarch | Legacy chart uyumu | Değerlendirme |
|---|---|---|---|---|
| Bitnami Elasticsearch | Bitnami packaging | amd64/arm64 tag'e bağlı | Doğal | Kaldırılması hedeflenen mevcut bağımlılık |
| Elastic official | Elastic License; Elastic tarafından güncellenir | amd64/arm64 sürüme bağlı | Düşük | ECK ile seçildi |
| OpenSearch | Apache-2.0 ekosistemi | amd64/arm64 sürüme bağlı | Yok | Kibana yerine Dashboards ve migration gerektirir |
| UBI tabanlı image | Vendor/community | Image'a bağlı | Düşük | Resmi ürün desteği ayrıca doğrulanmalı |
| Wolfi/hardened seçenek | Minimal CVE yüzeyi | Sürüme bağlı | Düşük | ECK/operator hardened seçenekleri production değerlendirmesine uygun |

Seçim resmi Elastic image + ECK'dir. Bunun nedeni ürünün Elasticsearch/Kibana olarak kalması, sürüm eşleştirmesi ve Kubernetes yaşam döngüsünün resmi operator tarafından yönetilmesidir.

Kaynaklar: [Elastic ECK installation](https://www.elastic.co/docs/deploy-manage/deploy/cloud-on-k8s/install), [Elastic self-managed installation](https://www.elastic.co/docs/deploy-manage/deploy/self-managed/installing-elasticsearch), [OpenSearch documentation](https://docs.opensearch.org/).
