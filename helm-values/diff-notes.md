# Values Değişiklik Notları

## Legacy

`original-values-oci-loyalty.yaml`, verilen dosyanın SHA-256 eş kopyasıdır. İki dosyada doğrulanan hash:

```text
4B9096ACFEA263FF23CB0DB570EAD110B77D4E0A4E4FEACBBF02B6B62C2D26D4
```

`image-override-only.yaml` yalnız analiz içindir ve deploy edilmemelidir.

Legacy topoloji 2 master, 2 data, 2 coordinating ve 2 ingest pod'u; ayrı Bitnami Kibana ve exporter kullanır. Güvenlik kapalı, image sürümleri ayrışmış ve resource limits tanımlanmamıştır.

## Aktif

`non-bitnami-values.yaml`:

- Tek `stack.version: 8.19.21`.
- Tek Elasticsearch node.
- Tek Kibana pod.
- `20Gi local-path` PVC.
- 8 GiB VPS'e göre sınırlandırılmış CPU/RAM.
- TLS/authentication ECK tarafından açık.
- Prometheus Community exporter ve external Secret.
- ServiceMonitor varsayılan kapalı.
- Public Ingress, NodePort ve LoadBalancer yok.
