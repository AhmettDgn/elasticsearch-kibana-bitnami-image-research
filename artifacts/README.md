# Artifacts

`scripts/collect-evidence.sh` gerçek sunucu testinde `YYYY-MM-DD` dizini oluşturur. Üretilen dosyalar varsayılan olarak Git tarafından ignore edilir; inceleyip hassas veri olmadığını doğruladıktan sonra gerekirse bilinçli olarak ekleyin.

2026-09-04 Contabo validasyonunda sunucuda `artifacts/2026-09-04/` altında `cluster-health.json`, `exporter-metrics.txt`, `kibana-status.json`, `nodes.txt`, `pods.txt`, `pvc.txt`, `report.md`, `search-result.json` ve `services.txt` üretildi. Sonuçların sanitize edilmiş özeti [`tests/integration/contabo-validation-2026-09-04.md`](../tests/integration/contabo-validation-2026-09-04.md) dosyasındadır.

Raw dosyaları commit etmeden önce password, token, Authorization header, Kubernetes Secret data, SSH key ve private IP bulunmadığını manuel doğrulayın.
