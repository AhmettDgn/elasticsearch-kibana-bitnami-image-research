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
- Kubeconform CI sonucu: 4 kaynak; standart Kubernetes kaynaklarında 2 valid, ECK CR'larında 2 schema olmadığı için skipped, 0 invalid ve 0 error.
- Gitleaks CI sonucu: secret leak bulunmadı.
- GitHub Actions `Validate` workflow sonucu: başarılı.
