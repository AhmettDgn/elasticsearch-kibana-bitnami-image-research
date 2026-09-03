# Helm Template Testi

Komut:

```bash
./tests/static/run.sh
```

Kontroller:

- Helm lint.
- Elasticsearch ve Kibana CR render'ı.
- Exporter Deployment/Service render'ı.
- Aktif render'da `docker.io/bitnami`, `/opt/bitnami` ve `/bitnami/` bulunmaması.
- Varsa kubeconform şema kontrolü.

## Yerel sonuç — 2026-09-03

- Helm: `v3.18.6`
- `helm lint`: başarılı, 1 chart lint edildi ve hata bulunmadı.
- `helm template`: Elasticsearch, Kibana, exporter Deployment ve ClusterIP Service üretildi.
- Varsayılan render: 4 Kubernetes kaynağı; ServiceMonitor kapalı.
- Elasticsearch/Kibana sürümü: `8.19.21`.
- Aktif render Bitnami runtime taraması: 0 eşleşme.
- ServiceMonitor capability testi: CRD capability yokken 0, capability verildiğinde 1 kaynak.
- Bütün Bash scriptleri `bash -n` syntax kontrolünü geçti.
- Deploy readiness regression testi; Elasticsearch `ApplyingChanges/unknown → green`, Kibana `red → green`, pod selector keşfi ve timeout diagnostics senaryolarını geçti.
- Exporter render'ında doğrulanmış numeric `runAsUser: 65534` ve `runAsGroup: 65534`; `runAsNonRoot`, `RuntimeDefault`, read-only root filesystem ve capability drop ile birlikte üretildi.
- Evidence regresyon testi; Elasticsearch/Kibana SAN hostname ve `--resolve`, doğru health/status/metrics endpointleri, search 404 sonrası partial-output ve credential sızıntısı olmamasını doğruladı.
- Ortak `demo-index` varsayılanı için HEAD preflight; index yokken açık hata/search skip ve index varken başarılı search evidence senaryoları doğrulandı.
- Metrics TLS/SAN regression testi; ECK public CA kullanımı, servis DNS hostname'i, configurable local port, `--resolve`, proxy bypass, retry hatası ve timeout diagnostics senaryolarını geçti.
- Kubeconform CI sonucu: 4 kaynak; standart Kubernetes kaynaklarında 2 valid, ECK CR'larında 2 schema olmadığı için skipped, 0 invalid ve 0 error.
- Gitleaks CI sonucu: secret leak bulunmadı.
- GitHub Actions `Validate` workflow sonucu: başarılı.
