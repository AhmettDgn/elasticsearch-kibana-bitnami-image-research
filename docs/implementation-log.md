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
- Contabo bootstrap gözlemine göre deploy readiness akışı düzeltildi: CR oluşumu, ECK health geçişleri, pod keşfi ve pod Ready kontrolleri birbirinden ayrıldı.
- Elasticsearch `unknown` ve Kibana `red` başlangıç durumları retry edilir; timeout/hata halinde otomatik diagnostics eklenir.
- Readiness state geçişleri ve diagnostics komutları için mock tabanlı regression testi eklendi.
- Gerçek Contabo deployment'ında Elasticsearch `green`, 1 node, `8.19.21`, `Ready`; Kibana `green`, 1 node ve pod `1/1 Running` olarak doğrulandı.
- Başarılı sonuç nedeniyle Helm/ECK resource creation davranışı korunarak değişiklik yalnız readiness/wait ve hata diagnostics katmanıyla sınırlandı.
- ECK HTTP sertifikası SAN uyuşmazlığı giderildi: port-forward kullanan scriptler HTTPS hostname olarak servis DNS adını ve `--resolve` kullanıyor; CA doğrulaması açık kalıyor.
- Metrics kullanıcı scriptine port-forward process kontrolü, görünür curl retry hatası ve cleanup öncesi timeout log dökümü eklendi.
- TLS/SAN, retry ve timeout davranışı için mock tabanlı regression testi eklendi.
- Metrics scriptindeki servis hostname değişkeni `ES_HOST` olarak standardize edildi; local port aralığı ve kullanım kontrolü ile dolu-port regresyon testi eklendi.
- Exporter `v1.11.0` image metadata'sı ve katmanındaki passwd/group kayıtları doğrulandı; `nobody` kullanıcısının UID/GID değeri `65534:65534` olarak exporter container securityContext'e configurable biçimde eklendi.
- Exporter kabul kontrolüne açık `/healthz` isteği eklendi; `/metrics` Elasticsearch metrik doğrulaması korundu.
- Paylaşılan özet sonuçlar test raporuna işlendi; sanitize edilmiş ham komut çıktıları ve screenshot'lar daha sonra `artifacts/` ile `screenshots/` dizinlerine eklenebilir.
