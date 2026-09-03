# Production Değerlendirmeleri

Bu deployment lab/PoC amaçlıdır. Tek VPS, tek K3s node, tek Elasticsearch node ve local disk kullanımı nedeniyle aşağıdaki riskler kabul edilir:

- Fiziksel host veya disk kaybında hizmet ve veri kaybı.
- Bakım/restart sırasında kesinti.
- Elasticsearch replica shard kullanamama.
- K3s control plane ile workload'un aynı kaynakları paylaşması.

Production için öneriler:

1. En az üç failure-domain'e dağıtılmış Kubernetes worker ve üç master-eligible Elasticsearch node.
2. Kullanım ölçümüne dayalı CPU, heap, disk watermark ve shard kapasite planı.
3. S3-compatible object storage üzerinde düzenli snapshot repository; restore tatbikatı ve retention politikası.
4. Prometheus/Grafana, alert kuralları, disk/heap/cluster health izleme ve merkezi loglama.
5. NetworkPolicy, dış secret manager, least-privilege kullanıcılar ve düzenli credential rotation.
6. Sürüm yükseltmeleri için staging, snapshot, compatibility kontrolü ve geri dönüş runbook'u.
7. StorageClass'ın disk/node arızası dayanıklılığı ve backup kapsamının ayrıca doğrulanması.

`local-path` yalnız pod yeniden oluşturulduğunda aynı node diskindeki veriyi korur; backup değildir.
