# Bitnami Path, Script ve Template Riskleri

## Runtime bağımlılıkları

Legacy StatefulSet ve Deployment template'lerinde aşağıdaki varsayımlar bulunur:

- `/opt/bitnami/scripts/elasticsearch/healthcheck.sh`
- `/opt/bitnami/scripts/elasticsearch/entrypoint.sh`
- `/opt/bitnami/elasticsearch/config/elasticsearch.yml`
- `/bitnami/elasticsearch/data`
- `/opt/bitnami/kibana/config`
- `/bitnami/kibana`
- `BITNAMI_DEBUG`, `ELASTICSEARCH_*` ve `KIBANA_*` environment değişkenleri

Resmi Elastic image'ları bu entrypoint sözleşmesini ve dizin yapısını sunmaz. Render işlemi YAML üretebilse bile pod başlangıcı, config mount, probe veya veri yolu aşamasında hata beklenir.

## Template bağımlılıkları

`common.images.*`, `common.names.*`, `common.labels.*`, `common.capabilities.*`, `common.tplvalues.*`, affinity ve validation helper'ları chart'ın geniş bölümüne dağılmıştır. Bunların kaldırılması bir image override değil, chart yeniden tasarımıdır.

## Kabul kontrolü

Static test yalnız aktif chart render'ında şu pattern'leri yasaklar:

```text
docker.io/bitnami
/opt/bitnami
/bitnami/
```

Legacy ve analiz belgeleri bilerek bu taramanın dışındadır.
