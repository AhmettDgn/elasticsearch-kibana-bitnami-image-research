# Contabo Uçtan Uca Validasyon Raporu — 2026-09-04

## Kapsam

Bu rapor, Bitnami bağımlılıkları aktif deployment'tan çıkarıldıktan sonra ECK tabanlı çözümün gerçek Contabo K3s ortamındaki uygulama ve test sonucunu özetler. Parola, token, Secret verisi, Authorization header, SSH anahtarı veya private IP içermez.

## Test ortamı

| Alan | Değer |
|---|---|
| İşletim sistemi | Ubuntu 24.04.4 LTS |
| Mimari | amd64/x86_64 |
| Sunucu | Contabo VPS, tek fiziksel node |
| Kaynak | 4 vCPU, 7.8 GiB RAM, swap disabled |
| Kubernetes | K3s `v1.36.4+k3s1` |
| StorageClass | `local-path` |
| `vm.max_map_count` | `1048576` |
| ECK operator | `3.5.0` |
| Elasticsearch/Kibana | `8.19.21` / `8.19.21` |
| Exporter | Prometheus Elasticsearch Exporter `1.11.0` |

İlk kontrolde mevcut Kafka, Jenkins, K3s ve VS Code Remote süreçleri nedeniyle yaklaşık 4.2–4.6 GiB RAM kullanılıyordu. Üç Kafka pod'u `replicas=0` yapılıp Jenkins geçici olarak durdurulduktan sonra available RAM yaklaşık 6.1 GiB oldu. Bu işlemler kullanıcı tarafından kontrollü yapıldı; proje otomasyonu mevcut servisleri durdurmaz.

## Sonuç özeti

| Test | Sonuç | Kanıt |
|---|---|---|
| TLS ve authentication | Başarılı | ECK CA + geçerli servis SAN hostname'i |
| Elasticsearch root endpoint | Başarılı | Version `8.19.21` |
| Cluster health | Başarılı | `green`, 1 node, 0 unassigned shard, `%100` active shard |
| Index | Başarılı | `demo-index`, replica 0, acknowledged/shards acknowledged |
| Document | Başarılı | `_id=1`, result `created`, 1 successful shard, 0 failed shard |
| Search | Başarılı | 1 hit; `source=eck`, `stack_version=8.19.21` |
| Kibana | Başarılı | health `green`, `/api/status` overall `available` |
| Exporter | Başarılı | pod `1/1 Running`, ClusterIP `9114`, Elasticsearch metrikleri mevcut |
| PVC | Başarılı | `20Gi`, `Bound`, `local-path` |
| Helm idempotency | Başarılı | Tekrarlı `deploy.sh` ve release upgrade tamamlandı |
| Persistence | Başarılı | Pod recreation sonrası `demo-index/_doc/1 found=true` |
| Static/regression | Başarılı | Helm lint ve tüm regression testleri geçti |

Test document içeriği:

```json
{
  "message": "hello from non-bitnami image test",
  "source": "eck",
  "stack_version": "8.19.21"
}
```

Exporter üzerinde doğrulanan metrik aileleri arasında şunlar bulunur:

- `elasticsearch_cluster_health_active_primary_shards`
- `elasticsearch_cluster_health_active_shards`
- `elasticsearch_cluster_health_number_of_data_nodes`
- Elasticsearch circuit breaker metrikleri

## Evidence manifesti

`collect-evidence.sh`, gerçek sunucuda `artifacts/2026-09-04/` altında aşağıdaki sanitize edilmiş dosyaları üretmiştir:

- `cluster-health.json`
- `exporter-metrics.txt`
- `kibana-status.json`
- `nodes.txt`
- `pods.txt`
- `pvc.txt`
- `report.md`
- `search-result.json`
- `services.txt`

Raw evidence dizini repository politikasına göre Git tarafından ignore edilir. Dosyalar yalnız password/token/Secret/private IP kontrolünden sonra bilinçli olarak paylaşılmalıdır.

## Görsel kanıtlar

Repository'ye eklenen 10 sanitize edilmiş terminal görüntüsü; pod health, ECK resource status, PVC, cluster health, exporter metrics, index, search, Kibana status, persistence ve static test sonuçlarını kapsar. Her görüntünün teknik açıklaması [`screenshots/README.md`](../../screenshots/README.md) dosyasındadır. Açık public veya Kubernetes iç ağ IP'si içeren kaynak görüntüler paylaşılmamış; servis tipi kanıtı server-local `services.txt` ve sanitize edilmiş rapor sonucunda korunmuştur.

Kibana UI görüntüsü Windows tarafındaki erişim/sertifika kısıtı nedeniyle alınamadı. Bu eksiklik fonksiyonel başarısızlık olarak değerlendirilmedi; Kibana CR health `green`, pod `1/1 Running` ve TLS doğrulamalı `/api/status` sonucu `overall.level=available` ile servis kullanılabilirliği kanıtlandı.

## Kabul kararı

Aktif Helm render'ında ve çalışan ECK deployment'ında Bitnami image, Bitnami Common/Kibana sub-chart, helper image, `/opt/bitnami` veya `/bitnami` runtime path bağımlılığı bulunmamaktadır. ECK Operator, resmi Elastic image'ları ve Kubernetes-native Secret/securityContext/persistence yaklaşımı gerçek ortamda başarıyla doğrulanmıştır.

Bu sonuç lab/single-node kapsamındadır. Fiziksel node, Elasticsearch node veya disk redundancy yoktur. `local-path` PVC pod recreation sırasında veriyi korumuştur; fiziksel VPS ya da disk kaybına karşı HA veya backup sağlamaz. Production ortamında remote S3-compatible snapshot repository, düzenli restore tatbikatı, retention politikası ve çok node'lu/failure-domain dağıtımlı mimari gereklidir.
