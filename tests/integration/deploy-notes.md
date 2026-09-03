# Deploy Notları

Contabo testi sırasında aşağıdakiler kaydedilecektir:

- K3s ve ECK sürümü.
- ECK operator readiness.
- Elasticsearch/Kibana/exporter pod durumu.
- PVC ve ClusterIP servisleri.
- Başlangıç süresi ve varsa event/hata analizi.

Secret ve credential değerleri rapora eklenmeyecektir.

## Gerçek Contabo sonucu

Düzeltme talebinden sonra mevcut Helm/ECK deployment başarıyla reconcile olmuştur:

| Kaynak | Health | Node/Pod | Sürüm | Phase |
|---|---|---:|---:|---|
| Elasticsearch | `green` | 1 node | `8.19.21` | `Ready` |
| Kibana | `green` | 1 node, pod `1/1 Running` | `8.19.21` | — |

Bu sonuç, Helm chart ve ECK resource creation akışının doğru olduğunu; hatanın yalnız eski `deploy.sh` readiness kontrolünün CR/pod oluşumundan önce veya uygun selector bulunmadan fail etmesinden kaynaklandığını doğrular. Bu nedenle Helm install/upgrade, ECK CR ve workload tanımları değiştirilmemiştir.

## Readiness davranışı

- Helm install sonrasında Elasticsearch ve Kibana CR'ları ayrı ayrı poll edilir.
- Elasticsearch `status.phase` ve `status.health` değişimleri loglanır; `unknown`/boş bootstrap durumları retry edilir ve yalnız `green` kabul edilir.
- Kibana başlangıçtaki `red`/boş durumunda retry edilir ve yalnız `green` kabul edilir.
- Pod selector'larıyla `kubectl wait` çağrılmadan önce en az bir eşleşen pod bulunması beklenir.
- Kibana selector'ı oluşturulan ECK pod'unun `kibana.k8s.elastic.co/name` label'ından tespit edilir.
- Health timeout varsayılan 900 saniye, pod readiness timeout 600 saniyedir.
- Timeout veya beklenmeyen komut hatasında CR, pod, PVC, service, describe, event ve son 150 operator log satırı otomatik yazdırılır.
