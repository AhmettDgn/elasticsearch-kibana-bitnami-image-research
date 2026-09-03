# Image Dependency Analizi

| Bileşen | Legacy image | Durum | Aktif karşılık |
|---|---|---|---|
| Elasticsearch | `bitnami/elasticsearch:8.2.0-debian-10-r14` | Aktif | ECK tarafından yönetilen resmi Elastic `8.19.21` |
| Curator | `bitnami/elasticsearch-curator:5.8.4-debian-10-r349` | Kapalı | Kapsam dışı; ILM tercih edilir |
| Metrics | `bitnami/elasticsearch-exporter:1.3.0-debian-10-r205` | Aktif | Prometheus Community `v1.11.0` |
| Volume permissions | `bitnami/bitnami-shell:10-debian-10-r432` | Aktif | `fsGroup` ve K3s local-path |
| Sysctl | `bitnami/bitnami-shell:10-debian-10-r432` | Aktif | Host sysctl configuration |
| Kibana | `bitnami/kibana:8.17.2-debian-12-r2` | Aktif | ECK tarafından yönetilen resmi Elastic `8.19.21` |
| Kibana permissions | `bitnami/os-shell:12-debian-12-r38` | Kapalı | Kubernetes security context |

Legacy values içindeki Elasticsearch `8.2.0` ve Kibana `8.17.2` sürüm ayrışması da düzeltilmiştir. Aktif chart'ta iki CR yalnız `stack.version` değerini kullanır.
