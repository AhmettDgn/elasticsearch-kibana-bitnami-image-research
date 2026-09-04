# Deploy Notları

## Doğrulanan ortam

- Ubuntu 24.04.4 LTS, amd64/x86_64.
- Contabo 4 vCPU / 7.8 GiB RAM, swap disabled, tek fiziksel node.
- K3s `v1.36.4+k3s1`, `local-path`, `vm.max_map_count=1048576`.
- ECK Operator `3.5.0`.

İlk ölçümde 4.2–4.6 GiB RAM kullanımı görüldü. Üç Kafka pod'u kullanıcı tarafından sıfıra ölçeklenip Jenkins geçici durdurulduktan sonra available RAM yaklaşık 6.1 GiB oldu. Otomasyon mevcut workload'lara müdahale etmedi.

Contabo testi sırasında aşağıdakiler kaydedildi:

- K3s ve ECK sürümü.
- ECK operator readiness.
- Elasticsearch/Kibana/exporter pod durumu.
- PVC ve ClusterIP servisleri.
- Başlangıç durumu, event ve hata analizi.

`collect-evidence.sh`, endpointleri bağımsız toplar. Bir endpoint 404 veya bağlantı hatası döndürürse daha önce oluşturulan dosyaları korur, kalan endpointleri dener, hatalı endpoint için `*.error.txt` ve `report.md` kaydı üretir; bütün kontroller tamamlandıktan sonra non-zero döner.

Secret ve credential değerleri rapora eklenmeyecektir.

## Gerçek Contabo sonucu

Düzeltme talebinden sonra mevcut Helm/ECK deployment başarıyla reconcile olmuştur:

| Kaynak | Health | Node/Pod | Sürüm | Phase |
|---|---|---:|---:|---|
| Elasticsearch | `green` | 1 node | `8.19.21` | `Ready` |
| Kibana | `green` | 1 node, pod `1/1 Running` | `8.19.21` | — |
| Exporter | `/healthz` ve `/metrics` başarılı | pod `1/1 Running` | `1.11.0` | — |
| PVC | `Bound` | `20Gi` | `local-path` | — |

Bu sonuç, Helm chart ve ECK resource creation akışının doğru olduğunu; hatanın yalnız eski `deploy.sh` readiness kontrolünün CR/pod oluşumundan önce veya uygun selector bulunmadan fail etmesinden kaynaklandığını doğrular. Bu nedenle Helm install/upgrade, ECK CR ve workload tanımları değiştirilmemiştir.

`deploy.sh` birden fazla kez çalıştırılmış; mevcut Helm release üzerinde upgrade, ECK reconcile ve workload readiness başarıyla tamamlanmıştır.

## Readiness davranışı

- Helm install sonrasında Elasticsearch ve Kibana CR'ları ayrı ayrı poll edilir.
- Elasticsearch `status.phase` ve `status.health` değişimleri loglanır; `unknown`/boş bootstrap durumları retry edilir ve yalnız `green` kabul edilir.
- Kibana başlangıçtaki `red`/boş durumunda retry edilir ve yalnız `green` kabul edilir.
- Pod selector'larıyla `kubectl wait` çağrılmadan önce en az bir eşleşen pod bulunması beklenir.
- Kibana selector'ı oluşturulan ECK pod'unun `kibana.k8s.elastic.co/name` label'ından tespit edilir.
- Health timeout varsayılan 900 saniye, pod readiness timeout 600 saniyedir.
- Timeout veya beklenmeyen komut hatasında CR, pod, PVC, service, describe, event ve son 150 operator log satırı otomatik yazdırılır.
