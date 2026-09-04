# Elasticsearch Health Testi

`scripts/verify.sh`, ECK CA ve yönetilen kullanıcıyla TLS üzerinden `_cluster/health` çağrısı yapar. Tek node test index'inde replica sayısı sıfır olduğu için beklenen durum `green`'dir.

## Gerçek Contabo sonucu — 2026-09-04

- Elasticsearch version: `8.19.21`.
- Status: `green`.
- Node sayısı: `1`.
- Unassigned shard: `0`.
- Active shards percent: `100`.
- ECK phase: `Ready`.

Gerçek çıktı sunucuda `artifacts/2026-09-04/cluster-health.json` altında toplandı. Raw artifacts Git tarafından varsayılan olarak ignore edilir.
