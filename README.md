# Bitnami'siz ECK Tabanlı Elasticsearch & Kibana

Bu repository, eski Bitnami Elasticsearch Helm chart'ındaki image, path, entrypoint ve helper bağımlılıklarını inceler ve çalışan sistemi resmi Elastic image'larını yöneten ECK tabanlı bir chart ile değiştirir.

## Sonuç

Yalnız image override yeterli değildir. Eski chart; Bitnami'ye özel `ELASTICSEARCH_*`/`KIBANA_*` değişkenlerini, `/opt/bitnami` scriptlerini, `/bitnami` veri yollarını ve `common` template kütüphanesini çalışma zamanında bekler. Aktif çözüm bu bağımlılıkları taşımayan yeni [ECK](https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html) kaynaklarıdır.

```text
Helm chart
  ├── Elasticsearch CR ─┐
  ├── Kibana CR ────────┴──> ECK 3.5.0 ──> Official Elastic 8.19.21 images
  └── Exporter Deployment ──> Elasticsearch /metrics
```

Hedef ortam Ubuntu amd64 üzerinde tek K3s node'dur. Bu bir lab/PoC topolojisidir; yüksek erişilebilirlik sağlamaz.

## Bileşenler

| Bileşen | Sürüm | Amaç |
|---|---:|---|
| K3s | `v1.36.4+k3s1` (doğrulanan ortam) | Tek sunuculu Kubernetes |
| ECK operator | `3.5.0` | Elasticsearch/Kibana yaşam döngüsü |
| Elasticsearch | `8.19.21` | Tek node arama ve veri servisi |
| Kibana | `8.19.21` | Görselleştirme arayüzü |
| elasticsearch_exporter | `1.11.0` | Prometheus metrik endpoint'i |

Bootstrap scriptinin varsayılan K3s sürümü `v1.36.3+k3s1` olarak sabittir ve `K3S_VERSION` ile değiştirilebilir. Gerçek Contabo validasyonu, sunucudaki `v1.36.4+k3s1` sürümü üzerinde tamamlanmıştır.

## Gerçek Contabo doğrulaması

Çözüm 4 vCPU, 7.8 GiB RAM, swap kapalı Ubuntu 24.04.4 LTS amd64 Contabo VPS üzerinde uygulanmıştır. Deployment öncesinde Kafka pod'ları sıfıra ölçeklenmiş ve Jenkins geçici olarak durdurularak kullanılabilir RAM yaklaşık 6.1 GiB seviyesine çıkarılmıştır. Otomasyon mevcut workload'ları kendiliğinden durdurmamıştır.

| Kontrol | Doğrulanan sonuç |
|---|---|
| Elasticsearch | `8.19.21`, 1 node, `phase=Ready`, health `green` |
| Cluster | 0 unassigned shard, `%100` active shard |
| Index/document/search | `demo-index`, replica 0, document `_id=1`, 1 search hit |
| Kibana | `8.19.21`, 1 pod, health `green`, `/api/status=available` |
| Exporter | `1.11.0`, pod `1/1 Running`, `/metrics` üzerinde gerçek Elasticsearch metrikleri |
| Storage | `20Gi local-path` PVC, `Bound` |
| Idempotency | Tekrarlı `helm upgrade`/`deploy.sh` başarılı |
| Persistence | Elasticsearch pod recreation sonrası `demo-index/_doc/1 found=true` |
| Bitnami bağımlılığı | Aktif render ve runtime'da image/helper/chart/path bağımlılığı yok |

Ayrıntılı hata analizi ve test kanıt özeti: [Contabo validasyon raporu](tests/integration/contabo-validation-2026-09-04.md). Kronolojik uygulama kaydı: [implementation log](docs/implementation-log.md).

## Hızlı başlangıç

Sunucuda en az 4 GiB kullanılabilir RAM ve 30 GiB boş disk bulunduğunu doğrulayın. Ayrıntılı ve açıklamalı akış için [Contabo runbook](docs/contabo-runbook.md) dosyasını kullanın.

```bash
git clone https://github.com/AhmettDgn/elasticsearch-kibana-bitnami-image-research.git
cd elasticsearch-kibana-bitnami-image-research
sudo ./scripts/bootstrap-k3s.sh
./scripts/deploy.sh
./scripts/verify.sh
./scripts/collect-evidence.sh
```

Gerçek testte sanitize edilmiş evidence dosyaları sunucuda `artifacts/2026-09-04/` altında oluşturulmuştur. Bu dizin credential sızıntısı riskine karşı varsayılan olarak Git tarafından ignore edilir; dosyalar ancak manuel içerik kontrolünden sonra paylaşılmalıdır.

Static test:

```bash
./tests/static/run.sh
```

Persistence ve idempotency testi kontrollü olarak Elasticsearch pod'unu yeniden oluşturur:

```bash
./tests/resilience/run.sh
```

## Güvenli erişim

Servisler yalnız `ClusterIP` tipindedir. Sunucuda port-forward çalıştırıp kendi bilgisayarınızdan SSH tüneli açın. Parola ve Secret çıktısını screenshot veya artifact içine almayın.

```bash
kubectl -n elastic-stack port-forward service/elastic-stack-kb-http 5601:5601 --address 127.0.0.1
```

```bash
ssh -L 5601:127.0.0.1:5601 ubuntu@SUNUCU_IP
```

Kibana: `https://localhost:5601`

## Dizinler

- `charts/elastic-stack`: Aktif, Bitnami'siz Helm chart.
- `legacy-chart/bitnami-elasticsearch`: İncelenen eski chart'ın değişmemiş kopyası.
- `chart-analysis`: Dependency ve runtime bağımlılık raporları.
- `alternatives`: Image/yaklaşım karşılaştırmaları ve seçim gerekçesi.
- `helm-values`: Orijinal values, yalnız image override deneyi ve aktif values.
- `scripts`: K3s, deployment, doğrulama ve kanıt toplama otomasyonu.
- `tests`: Static, integration ve resilience testleri.
- `docs`: Mimari, runbook, çalışma günlüğü ve production önerileri.

## Önemli sınırlar

- Tek fiziksel VPS ve tek Elasticsearch node nedeniyle HA yoktur.
- `local-path` PVC pod yeniden oluşturulmasına karşı veriyi korur; VPS veya disk kaybına karşı korumaz.
- Production için en az üç uygun node, harici snapshot repository, merkezi monitoring, kapasite testi ve kontrollü upgrade politikası gerekir.
- Public repoya parola, token, Secret verisi, SSH anahtarı veya Authorization header commit edilmemelidir.
