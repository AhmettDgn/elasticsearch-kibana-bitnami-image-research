# Mimari

```text
Laptop
  └── SSH tunnel
        └── Contabo Ubuntu / K3s (single node)
              ├── ECK operator 3.5.0
              └── elastic-stack namespace
                    ├── Elasticsearch 8.19.21 (1 pod)
                    │     └── 20Gi local-path PVC
                    ├── Kibana 8.19.21 (1 pod)
                    └── elasticsearch_exporter 1.11.0
```

Elasticsearch ve Kibana HTTP endpoint'leri ECK tarafından üretilen TLS sertifikaları ve authentication ile korunur. Servis tipi ClusterIP'tir. Exporter, Kubernetes Secret'taki minimum yetkili kullanıcıyı ve ECK public CA secret'ını kullanır.

Tek node mimarisi shard replica veya fiziksel dayanıklılık sağlamaz. Test index'i bu nedenle `number_of_replicas: 0` ile oluşturulur ve sağlıklı durumda cluster `green` olur.
