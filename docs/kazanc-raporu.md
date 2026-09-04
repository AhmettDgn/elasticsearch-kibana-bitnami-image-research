# Bitnami'den ECK'ye Geçiş Kazanç Raporu

## Yönetici özeti

Bu çalışmanın kazancı yalnızca Bitnami image'larının değiştirilmesi değildir. Elasticsearch ve Kibana yaşam döngüsü, Bitnami'ye özgü chart, entrypoint, helper ve dosya sistemi varsayımlarından çıkarılarak Elastic'in Kubernetes için geliştirdiği ECK operator modeline taşınmıştır.

Aktif çözüm; ECK `3.5.0`, resmi Elasticsearch ve Kibana `8.19.21` image'ları, Prometheus Community Elasticsearch Exporter `1.11.0` ve Kubernetes-native güvenlik/persistence bileşenlerinden oluşmaktadır. Çözüm gerçek Contabo ortamında deployment, TLS, authentication, index/document/search, metrics, idempotency ve pod recreation sonrası persistence açısından doğrulanmıştır.

> Önceden Kubernetes üzerinde Bitnami'nin Elasticsearch ve Kibana'yı nasıl paketlediğine bağımlıydık; şimdi bu ürünlerin Kubernetes yaşam döngüsünü Elastic'in resmi operator'ü yönetiyor.

## Önce ve sonra

| Alan | Eski Bitnami yaklaşımı | Yeni ECK yaklaşımı | Kazanç |
|---|---|---|---|
| Elasticsearch yönetimi | Genel amaçlı Helm template'leri | Elasticsearch-aware ECK reconciliation | Ürün durumunu gözeten declarative yaşam döngüsü |
| Kibana entegrasyonu | Bitnami sub-chart ve values bağımlılığı | Kibana CR ve `elasticsearchRef` | Elasticsearch bağlantısının daha doğal yönetilmesi |
| Container image | `bitnami/elasticsearch`, `bitnami/kibana` | Resmi Elastic image'ları | Üçüncü taraf runtime sözleşmesi kaldırıldı |
| Runtime yolları | `/opt/bitnami`, `/bitnami` | Resmi Elastic layout | Path ve entrypoint teknik borcu kaldırıldı |
| Helm bağımlılıkları | Bitnami `common` ve Kibana sub-chart | Bağımsız aktif chart ve ECK CR'ları | Daha küçük ve açık deployment yüzeyi |
| TLS | Chart/values/script sorumluluğu | ECK tarafından varsayılan yönetim | Güvenli varsayılan ve daha az manuel işlem |
| Authentication | Values/env/Secret tasarımı | ECK tarafından oluşturulan kullanıcı ve Secret'lar | Credential yönetiminin sadeleşmesi |
| Sertifikalar | Harici veya manuel yaşam döngüsü ihtiyacı | ECK tarafından yönetilen CA ve sertifikalar | Yenileme operasyonunun operator katmanına taşınması |
| Sürüm yönetimi | Elasticsearch `8.2.0`, Kibana `8.17.2` | Ortak `stack.version: 8.19.21` | Sürüm drift'inin kaldırılması |
| Sysctl | Privileged Bitnami helper image | Host üzerinde kalıcı `vm.max_map_count` | Gereksiz privileged helper kaldırıldı |
| Volume izinleri | Bitnami shell/os-shell helper'ları | `securityContext`, `fsGroup`, `local-path` | Kubernetes-native izin modeli |
| Metrics | Bitnami exporter | Prometheus Community exporter | Bitnami runtime bağımlılığı olmadan gözlemlenebilirlik |
| Pod recovery | Kubernetes pod davranışı | Kubernetes ve ECK reconciliation | Elasticsearch sağlık durumuyla birlikte recovery takibi |
| Troubleshooting | Chart, sub-chart ve Bitnami script katmanları | CR status, operator logları ve Kubernetes olayları | Sorun alanının daha görünür olması |

## Somut ve ölçülebilir kazanımlar

| Gösterge | Önce | Sonra | Doğrulama |
|---|---:|---:|---|
| Aktif Bitnami image/chart/helper bağımlılığı | Birden fazla | `0` | Aktif Helm render taraması |
| Legacy override sonrasında kalan Bitnami runtime path eşleşmesi | `15` | Aktif chart'ta `0` | Static image-override ve deployment regression testleri |
| Stack sürüm kaynağı | Ayrı ES/Kibana değerleri | `1` ortak değer | `stack.version: 8.19.21` |
| Elasticsearch/Kibana sürüm farkı | `8.2.0` / `8.17.2` | `8.19.21` / `8.19.21` | ECK CR status |
| Elasticsearch sağlık sonucu | Legacy için bu çalışmada deploy kabulü yok | `green`, 1 node, 0 unassigned shard | Gerçek Contabo testi |
| Kalıcılık kanıtı | Belirsiz | Pod recreation sonrası document `found=true` | Resilience testi |
| Deployment tekrarlanabilirliği | Legacy kapsamı dışında | Tekrarlı `deploy.sh` ve Helm upgrade başarılı | Idempotency testi |
| Metrics | Eski Bitnami exporter bağımlılığı | `/healthz` ve `/metrics` başarılı | Integration testi |

Bu değerler parasal tasarruf iddiası değildir. Projede önceki çözümün işletme süresi ve insan/saat maliyeti ölçülmediği için finansal yüzde verilmemiştir. Raporlanan kazançlar mimari sadeleşme, güvenlik varsayımları, operasyonel doğrulanabilirlik ve kaldırılan teknik bağımlılıklar üzerinden ölçülmüştür.

## 1. Elasticsearch-aware orchestration

Bitnami chart Kubernetes objeleri üretirken ECK, Elasticsearch ve Kibana için özel Custom Resource'ları izleyen bir controller çalıştırır. İstenen durum ile gerçek durum arasındaki farkı sürekli reconcile eder.

```text
Desired state
    ↓
Elasticsearch / Kibana CR
    ↓
ECK Operator
    ↓
StatefulSet / Deployment / Service / Secret / TLS
    ↓
Actual state
    ↑
    └──────── reconciliation ────────┘
```

Gerçek resilience testinde Elasticsearch pod'u kontrollü olarak silinmiş, ECK/Kubernetes yeni pod'u oluşturmuş, cluster geçici `red` durumundan `green` durumuna dönmüş ve aynı document yeniden okunmuştur. Böylece yalnız `Pod Running` değil, Elasticsearch'ün gerçekten sağlıklı ve verinin erişilebilir olduğu doğrulanmıştır.

## 2. Güvenlik kazancı

Yeni deployment'ta:

- Elasticsearch ve Kibana HTTPS ile çalışır.
- HTTP sertifikaları ve CA, ECK tarafından yönetilir.
- Authentication açıktır.
- Elasticsearch transport iletişimi ECK güvenlik modeli içindedir.
- Kibana, Elasticsearch'e ECK referansı üzerinden bağlanır.
- Exporter ayrı ve minimum yetkili `monitor` kullanıcısını kullanır.
- Parolalar values, GitHub, log, screenshot veya evidence dosyalarına yazılmaz.
- Elasticsearch ve Kibana servisleri yalnız `ClusterIP` olarak sunulur.
- Dış erişim SSH tüneli veya kontrollü port-forward ile yapılır.

TLS testlerinde `-k`/`--insecure` kullanılmamıştır. ECK sertifikasındaki geçerli Kubernetes servis DNS SAN değeri ve `--resolve` kullanılarak CA ve hostname doğrulaması korunmuştur. Bu, güvenliğin test kolaylığı uğruna devre dışı bırakılmadığını gösterir.

## 3. Sertifika yaşam döngüsü kazancı

CA, HTTP ve transport sertifikalarının oluşturulması ve operator tarafından yönetilmesi uygulama scriptlerinden ayrılmıştır. Böylece sertifika üretme, servislerle ilişkilendirme ve yenileme sorumluluğu Elasticsearch/Kibana yaşam döngüsünü bilen katmana taşınmıştır.

Bu kazanım “sertifikalarla hiç ilgilenilmeyecek” anlamına gelmez. Production ortamında sertifika geçerlilik politikaları, operator upgrade'ları ve gerektiğinde kurumsal CA entegrasyonu yine takip edilmelidir.

## 4. Sürüm ve upgrade yönetimi kazancı

Eski yapıda Elasticsearch `8.2.0`, Kibana ise `8.17.2` olarak tanımlanmıştı. Yeni chart'ta iki ürün de tek kaynaktan sürüm alır:

```yaml
stack:
  version: "8.19.21"
```

Bu yaklaşım yanlışlıkla sürüm ayrışması oluşturulmasını önler. ECK, Elastic bileşenlerinin rollout ve reconciliation işlemlerini ürün farkındalığıyla yürütmek için uygun yönetim katmanını sağlar.

Her upgrade yine staging testi, snapshot, uyumluluk kontrolü ve rollback planı gerektirir. ECK kontrollü bir upgrade yolu sağlar; upgrade riskini tamamen ortadan kaldırmaz.

## 5. Bitnami teknik borcunun kaldırılması

Eski chart aşağıdaki packaging ayrıntılarına bağlıydı:

- Bitnami entrypoint ve startup scriptleri
- Bitnami'ye özgü environment variable'lar
- `/opt/bitnami/...` healthcheck ve çalışma yolları
- `/bitnami/...` veri yolları
- Bitnami `common` helper template'leri
- Bitnami volume-permissions ve sysctl image'ları
- Bitnami Kibana sub-chart'ı

Yalnız image override deneyi bu sözleşmeleri ortadan kaldırmamıştır; legacy render'da 15 runtime path eşleşmesi kalmıştır. Bu nedenle override, çalışan final çözüm değil, uyumsuzluğu gösteren migration kanıtıdır.

Aktif ECK chart'ının render çıktısında `docker.io/bitnami`, `/opt/bitnami` ve `/bitnami/` bulunmadığı static testlerle doğrulanmıştır.

## 6. Operasyon ve troubleshooting kazancı

Yeni modelde kontrol noktaları daha nettir:

```text
kubectl get elasticsearch,kibana
kubectl describe elasticsearch
kubectl get pods,pvc,svc
kubectl get events
kubectl logs statefulset/elastic-operator
```

Deployment scripti başlangıçtaki doğal `unknown`, `red` ve `ApplyingChanges` geçişlerini hata saymaz; CR oluşumunu, ECK health durumunu ve pod readiness'i ayrı ayrı bekler. Timeout halinde tanılama çıktıları üretir. Bu, bootstrap yarış durumlarını gerçek deployment hatalarından ayırır.

## 7. Büyüme ve production yolu

Mevcut `nodeSets.count: 1` topolojisi 4 vCPU/7.8 GiB RAM Contabo lab ortamı için bilinçli olarak seçilmiştir. Daha büyük bir Kubernetes altyapısında ECK ile farklı roller, daha fazla node ve failure-domain dağılımı declarative olarak modellenebilir.

ECK mimarisi autoscaling gibi gelişmiş kabiliyetlere geçiş yolu da sağlar; ancak bazı özellikler Elastic lisans seviyesine bağlıdır. Bu nedenle ücretsiz veya otomatik olarak kullanılabildiği varsayılmamalı, hedef sürümün güncel lisans koşulları ayrıca doğrulanmalıdır.

## 8. Backup ve dayanıklılık açısından kazanım

`20Gi local-path` PVC, Elasticsearch pod'u yeniden oluşturulduğunda document'in korunmasını sağlamıştır. Bu, workload seviyesinde kalıcılık kazancıdır; backup veya yüksek erişilebilirlik değildir.

Production için doğal sonraki adım:

```text
Elasticsearch
    ├── local/CSI PVC
    └── zamanlanmış snapshot
              ↓
       S3-compatible object storage
```

Snapshot retention, encryption, erişim politikası ve düzenli restore tatbikatı production tasarımının parçası olmalıdır.

## Geçişin maliyetleri ve yeni sorumluluklar

Profesyonel değerlendirme yalnız faydaları değil, eklenen sorumlulukları da içerir:

| Maliyet / risk | Etki | Yönetim yaklaşımı |
|---|---|---|
| Operator bağımlılığı | Reconciliation, sertifika ve upgrade işlemleri ECK'ye bağlıdır | Operator health ve logları izlenmeli |
| Cluster-wide CRD'ler | Kurulum ve upgrade için uygun Kubernetes yetkisi gerekir | CRD/operator değişiklikleri kontrollü yürütülmeli |
| Öğrenme eğrisi | CR status ve reconciliation davranışı bilinmelidir | Runbook ve diagnostics komutları kullanılmalı |
| Operator upgrade'ı | ECK sürümü ayrıca yaşam döngüsüne sahiptir | Uyumluluk matrisi ve bakım penceresi uygulanmalı |
| Lisans sınırları | Bazı gelişmiş özellikler ücretli katman gerektirebilir | Özellik bazında güncel lisans doğrulaması yapılmalı |
| Tek node lab sınırı | Fiziksel node ve disk arızasında kesinti/veri kaybı riski vardır | Multi-node production ve remote snapshot kullanılmalı |

ECK “sıfır operasyon” çözümü değildir. Kazancı, Elasticsearch ve Kibana operasyonlarını Kubernetes üzerinde ürün-farkındalıklı, declarative ve daha doğrulanabilir hale getirmesidir.

## Kazançların kanıt matrisi

| Kazanç | Projedeki kanıt |
|---|---|
| Bitnami runtime bağımlılığının kaldırılması | [`tests/static/helm-template-output.md`](../tests/static/helm-template-output.md) |
| Image override'ın yetersizliği | [`tests/static/image-override-analysis.md`](../tests/static/image-override-analysis.md) |
| ECK mimarisi | [`docs/architecture.md`](architecture.md) |
| Gerçek deployment kabulü | [`tests/integration/contabo-validation-2026-09-04.md`](../tests/integration/contabo-validation-2026-09-04.md) |
| Cluster health | [`tests/integration/elasticsearch-health-test.md`](../tests/integration/elasticsearch-health-test.md) |
| Index/document/search | [`tests/integration/index-document-search-test.md`](../tests/integration/index-document-search-test.md) |
| Kibana kullanılabilirliği | [`tests/integration/kibana-test.md`](../tests/integration/kibana-test.md) |
| Metrics | [`tests/integration/metrics-exporter-test.md`](../tests/integration/metrics-exporter-test.md) |
| Pod recreation sonrası veri kalıcılığı | [`tests/resilience/persistence-test.md`](../tests/resilience/persistence-test.md) |
| Görsel doğrulama | [`screenshots/README.md`](../screenshots/README.md) |

## Sonuç

Bitnami'den ECK'ye geçiş, bir image değişikliğinden daha kapsamlı bir mimari iyileştirmedir. Aktif deployment üçüncü taraf filesystem, helper, entrypoint ve sub-chart varsayımlarından arındırılmış; resmi Elastic image'ları, ECK reconciliation, güvenli TLS/authentication varsayımları ve Kubernetes-native izin/persistence modeliyle yeniden kurulmuştur.

Mevcut Contabo lab ortamındaki en somut kazanımlar şunlardır:

1. Aktif sistemde sıfır Bitnami runtime bağımlılığı.
2. Elasticsearch ve Kibana için tek ve eşit sürüm kaynağı.
3. ECK tarafından yönetilen TLS, authentication ve resource reconciliation.
4. Minimum yetkili ve Secret tabanlı exporter erişimi.
5. Tekrarlanabilir Helm deployment ve açıklayıcı readiness/diagnostics akışı.
6. Gerçek Elasticsearch health, data, search, metrics ve persistence kanıtları.
7. Gelecekte çok node, snapshot ve daha gelişmiş topolojilere geçiş için daha temiz bir temel.

Sonuç olarak proje, Bitnami bağımlılığını yalnız görünürde değil aktif render ve runtime katmanında kaldırmış; bunun karşılığında yönetilebilir bir ECK operator/CRD sorumluluğu kabul ederek daha güvenli, ürün-farkındalıklı ve sürdürülebilir bir operasyon modeli kazanmıştır.
