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
- Evidence endpointleri doğrulandı: Elasticsearch `/_cluster/health`, Kibana `/api/status`, exporter `/metrics`; opsiyonel index search 404 dahil endpoint hataları isim/path/HTTP koduyla raporlanıp kalan kanıtların toplanmasına devam ediliyor.
- Verify ve evidence scriptlerinin ortak varsayılan index adı `demo-index` yapıldı; evidence search öncesi `HEAD /demo-index` kontrolüyle eksik index genel 404 yerine açık önkoşul hatası olarak raporlanıyor.
- Verify exporter metrics kontrolü curl çıktısını önce geçici dosyaya alacak şekilde ayrıştırıldı; pipeline/SIGPIPE kaynaklı curl `23` yanlış negatifi kaldırıldı ve API başlangıç probe hataları retry süresince info seviyesine çekildi.
- Resilience pod recreation akışı yeni pod'u selector ve değişen UID ile poll ediyor; pod oluşmadan `kubectl wait` çalıştırmıyor, ardından pod Ready, ECK `Ready/green`, API erişimi ve restart öncesi/sonrası `found=true` persistence kontrollerini uyguluyor.
- Paylaşılan özet sonuçlar test raporuna işlendi; sanitize edilmiş ham komut çıktıları ve screenshot'lar daha sonra `artifacts/` ile `screenshots/` dizinlerine eklenebilir.

## 2026-09-04 — Gerçek Contabo uygulaması ve doğrulaması

### Ortam ve kaynak hazırlığı

Doğrulama Ubuntu 24.04.4 LTS, amd64/x86_64, 4 vCPU, 7.8 GiB RAM, swap kapalı tek Contabo VPS üzerinde yapıldı. Sunucuda K3s `v1.36.4+k3s1`, `local-path` StorageClass ve `vm.max_map_count=1048576` doğrulandı.

- **Problem:** İlk kontrolde yaklaşık 4.2–4.6 GiB RAM kullanılıyordu; Elasticsearch ve Kibana için güvenli çalışma payı yetersizdi.
- **Kök neden:** Üç Kafka pod'u, Jenkins Docker container'ı, K3s ve VS Code Remote aynı VPS kaynaklarını kullanıyordu.
- **Çözüm:** Kafka workload kullanıcı tarafından `replicas=0` seviyesine indirildi ve Jenkins geçici olarak durduruldu. Otomasyon mevcut servisleri kendiliğinden değiştirmedi.
- **Doğrulama:** Available RAM yaklaşık 6.1 GiB seviyesine çıktı ve deployment bu kapasiteyle başlatıldı.

### 1. ECK deployment readiness yarış durumu

- **Problem:** Helm ve ECK kaynakları oluşmasına rağmen ilk `deploy.sh` çalışması `error: no matching resources found` ile sonlandı.
- **Kök neden:** Elasticsearch/Kibana CR ve pod'ları henüz oluşturulmadan selector tabanlı `kubectl wait` çalışıyordu.
- **Çözüm:** CR creation polling, health retry, pod discovery kontrolü ve runtime Kibana selector keşfi eklendi. Elasticsearch için `health=green`, Kibana için `health=green` beklendi; timeout diagnostics eklendi.
- **Doğrulama:** Tekrarlı deployment'ta Elasticsearch `phase=Ready`, `health=green`, 1 node; Kibana `health=green`, pod `1/1 Running` oldu.

### 2. Elasticsearch TLS SAN uyuşmazlığı

- **Problem:** Loopback URL ile yapılan ilk curl çağrısı `SSL: no alternative certificate subject name matches target host name '127.0.0.1'` hatası verdi.
- **Kök neden:** ECK HTTP sertifikasında `127.0.0.1` SAN değeri yoktu; geçerli DNS SAN `elastic-stack-es-http.elastic-stack.svc` idi.
- **Çözüm:** ECK public HTTP CA kullanılmaya devam edilerek curl URL'si geçerli servis hostname'ine taşındı ve `--resolve <service-host>:<local-port>:127.0.0.1` kullanıldı. `-k`/`--insecure` eklenmedi.
- **Doğrulama:** Certificate hostname doğrulaması, authentication, Elasticsearch root endpoint ve cluster health çağrıları başarılı oldu.

### 3. İlk authentication 401 hatası

- **Problem:** İlk API çağrısı `unable to authenticate user [elastic]` ile HTTP 401 döndürdü.
- **Kök neden:** Yeni terminal oturumunda `ELASTIC_PASSWORD` shell değişkeni tanımlı değildi.
- **Çözüm:** Parola ECK tarafından yönetilen elastic-user Secret'tan geçici shell variable'a alındı; log, report veya artifact dosyasına yazılmadı.
- **Doğrulama:** Elasticsearch root endpoint ve `/_cluster/health` authenticated çağrıları başarıyla tamamlandı.

### 4. Metrics kullanıcı scriptinde TLS hostname hatası

- **Problem:** `configure-metrics-user.sh` port-forward sonrasında Elasticsearch API'ye erişemedi.
- **Kök neden:** Script `https://127.0.0.1:<port>` kullanarak ECK sertifikasının DNS SAN doğrulamasını ihlal ediyordu.
- **Çözüm:** `ES_HOST`, `--resolve`, CA doğrulaması, port collision kontrolü, port-forward process kontrolü ve görünür retry/timeout diagnostics eklendi.
- **Doğrulama:** Minimum yetkili exporter role/user oluşturuldu; credentials yalnız Kubernetes Secret içinde tutuldu ve idempotent tekrar çalıştırma mevcut parolayı korudu.

### 5. Exporter CreateContainerConfigError

- **Problem:** Exporter pod `CreateContainerConfigError` durumunda kaldı; event, non-numeric `nobody` kullanıcısıyla `runAsNonRoot` doğrulamasının yapılamadığını gösterdi.
- **Kök neden:** `ghcr.io/prometheus-community/elasticsearch-exporter:v1.11.0` image config'i `USER=nobody` kullanıyordu. Image katmanında bu kullanıcı UID/GID `65534:65534` olsa da kubelet isim tabanlı değeri numeric non-root olarak doğrulayamıyordu.
- **Çözüm:** Configurable container securityContext'e `runAsUser: 65534` ve `runAsGroup: 65534` eklendi. `runAsNonRoot`, `allowPrivilegeEscalation=false`, read-only root filesystem, `drop: ALL` ve `RuntimeDefault` seccomp korundu.
- **Doğrulama:** Exporter pod `1/1 Running`, servis `ClusterIP:9114`, `/healthz` ve `/metrics` başarılı oldu.

### 6. Exporter metrics curl 23 yanlış negatifi

- **Problem:** Exporter gerçek metrik üretirken verify akışı `curl: (23) Failure writing output to destination` ve “Exporter did not return Elasticsearch metrics” hatası verdi.
- **Kök neden:** `curl | grep -q` pipeline'ında grep ilk eşleşmede çıkınca downstream pipe kapandı ve curl exit 23 üretti.
- **Çözüm:** Curl yanıtı önce geçici dosyaya yazıldı; HTTP exit code ve dosya üzerindeki metric grep sonucu ayrı değerlendirildi. İlk Elasticsearch probe bağlantı hatası retry süresince info seviyesine çekildi.
- **Doğrulama:** `verify.sh` “All integration checks passed” sonucu verdi; regression testi curl 23 yanlış negatif senaryosunu kapsadı.

### 7. Evidence index adı uyuşmazlığı

- **Problem:** `collect-evidence.sh` search çağrısında HTTP 404 ile durdu.
- **Kök neden:** Evidence scripti `bitnami-free-demo`, verify akışı ise gerçek `demo-index` adını kullanıyordu.
- **Çözüm:** Ortak varsayılan `INDEX_NAME=demo-index` yapıldı, environment override korundu ve search öncesine authenticated/TLS-verified `HEAD /demo-index` kontrolü eklendi. Endpointler bağımsız toplanarak partial-output desteği sağlandı.
- **Doğrulama:** Evidence `artifacts/2026-09-04/` altında health, search, Kibana, exporter, node, pod, PVC ve service dosyalarıyla başarıyla üretildi.

### 8. Resilience pod recreation yarış durumu

- **Problem:** Elasticsearch pod silindikten hemen sonra selector ile `kubectl wait` çalıştı ve `error: no matching resources found` döndürdü.
- **Kök neden:** StatefulSet/ECK henüz yeni pod nesnesini oluşturmamıştı.
- **Çözüm:** Eski pod UID'si kaydedildi; aynı selector altında yeni UID'li pod görünene kadar polling yapıldı. Concrete pod için Ready beklendi, ardından ECK `phase=Ready`/`health=green` ve API erişimi retry ile doğrulandı.
- **Doğrulama:** Silme öncesi ve sonrası `demo-index/_doc/1 found=true` döndü; “Persistence and idempotency checks passed” sonucu alındı.

### 9. Final fonksiyonel kabul

- Elasticsearch `8.19.21`: TLS/authentication başarılı, cluster `green`, 1 node, 0 unassigned shard, active shard oranı `%100`.
- `demo-index`: `number_of_replicas=0`, index ve shard acknowledgement başarılı.
- Document `_id=1`: `created`, 1 başarılı shard, 0 başarısız shard; search sonucu 1 hit.
- Kibana `8.19.21`: health `green`, 1 pod, `/api/status` overall `available`.
- Exporter `1.11.0`: pod `1/1 Running`; cluster health ve circuit breaker dahil gerçek Elasticsearch metrikleri mevcut.
- PVC: `20Gi`, `Bound`, `local-path`; pod recreation sonrasında veri korundu.
- Idempotency: `deploy.sh` ve Helm release upgrade birden fazla kez başarıyla çalıştı.
- Static/regression: Helm lint 0 hata; deploy readiness, TLS/SAN, partial evidence, verify metrics ve resilience recreation testleri geçti; kubeconform 2 valid, 0 invalid, 0 error, 2 ECK CR schema skip sonucu verdi.

Detaylı sanitize edilmiş sonuç özeti [`tests/integration/contabo-validation-2026-09-04.md`](../tests/integration/contabo-validation-2026-09-04.md) dosyasındadır. Raw evidence sunucuda üretilmiş ve repository'nin varsayılan güvenlik politikası gereği Git'e otomatik eklenmemiştir.

### Görsel kanıt düzenlemesi

- 14 kaynak görüntü incelendi; birebir aynı exporter metrics görüntüsü ve daha az okunaklı Kibana status tekrarı elendi.
- Açık sunucu IP adresi içeren node/StorageClass görüntüsü public repository'ye alınmadı; ortam bilgileri sanitize edilmiş metin raporunda korundu.
- Açık Kubernetes iç ağ IP'leri içeren service görüntüsü de public repository kapsamından çıkarıldı; servis tipi kanıtı sanitize edilmiş rapor ve server-local `services.txt` içinde korundu.
- 10 benzersiz ve paylaşılabilir görüntü açıklayıcı adlarla `screenshots/` altına taşındı ve her birinin kanıtladığı durum `screenshots/README.md` içinde belgelendi.
- Windows üzerinden Kibana UI ekranı alınamadı; bunun yerine Kibana CR `green`, pod `1/1 Running` ve TLS doğrulamalı `/api/status=available` sonuçları kanıt olarak kullanıldı.

### Kazanç raporu

- Bitnami'den ECK'ye geçişin mimari, güvenlik, operasyon, sürüm yönetimi, troubleshooting ve büyüme etkileri ayrı bir kazanç raporunda toplandı.
- Kazançlar yalnız nitel ifadelerle bırakılmadı; aktif Bitnami bağımlılığı sayısı, legacy override path eşleşmeleri, tek sürüm kaynağı, green health, idempotency ve persistence gibi proje kanıtlarıyla ilişkilendirildi.
- Finansal ölçüm yapılmadığı için doğrulanmamış maliyet yüzdeleri kullanılmadı.
- Operator/CRD yönetimi, öğrenme eğrisi, lisans sınırları ve tek node riski geçişin maliyetleri olarak açıkça kaydedildi.
