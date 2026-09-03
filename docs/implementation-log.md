# Implementation Log

## 2026-09-03

- Verilen Bitnami Elasticsearch chart'ı ve `values-oci-loyalty.yaml` incelendi.
- Elasticsearch `8.2.0` ile Kibana `8.17.2` sürüm drift'i tespit edildi.
- Bitnami Common, Kibana sub-chart, helper image, environment, healthcheck ve runtime path bağımlılıkları çıkarıldı.
- Klasör bağımsız Git repository olarak başlatıldı; üst dizindeki ilgisiz Git repository'sinden ayrıldı.
- Orijinal chart `legacy-chart/bitnami-elasticsearch` altına taşındı.
- ECK CR'larını ve Prometheus Community exporter'ını üreten bağımsız `charts/elastic-stack` chart'ı oluşturuldu.
- Tek node, `20Gi local-path`, 8 GiB VPS resource profili ve tek `stack.version` uygulandı.
- K3s bootstrap, deploy, minimum yetkili metrics kullanıcısı, doğrulama ve temiz kanıt toplama scriptleri eklendi.
- Static, integration ve resilience test katmanları eklendi.
- Contabo runbook, mimari ve production/snapshot önerileri yazıldı.
- Resmi Helm `v3.18.6` paketi yayınlanan SHA-256 checksum ile doğrulandı ve geçici dizinden kullanıldı.
- Aktif chart `helm lint` ve `helm template` testlerini geçti; aktif render'da Bitnami runtime pattern'i bulunmadı.
- Legacy image override render'ında 15 Bitnami runtime path eşleşmesi bulunarak yalnız override yaklaşımının yetersizliği doğrulandı.
- Public GitHub repository oluşturuldu, `origin` bağlandı ve `main` push edildi.
- GitHub Actions Helm/render/schema kontrolleri ile Gitleaks secret taraması başarılı oldu.
- GitHub Actions bağımlılıkları güncel resmi sürümlerin immutable commit SHA'larına sabitlendi.
- Gerçek Contabo sonuçları kullanıcı testinden sonra `artifacts/` ve test raporlarına eklenecektir.
