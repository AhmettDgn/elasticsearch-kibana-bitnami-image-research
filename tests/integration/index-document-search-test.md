# Index, Document ve Search Testi

Test akışı:

1. Varsayılan `demo-index` index'i `number_of_replicas: 0` ile oluşturulur. `INDEX_NAME` environment variable ile hem doğrulama hem evidence scriptlerinde değiştirilebilir.
2. Sabit ID'li örnek document `refresh=wait_for` ile eklenir.
3. `_search?q=_id:1` çağrısında beklenen mesaj doğrulanır.

## Gerçek Contabo sonucu — 2026-09-04

- `demo-index` oluşturma: `acknowledged=true`, `shards_acknowledged=true`, health `green`.
- Replica sayısı: `0`.
- Document: `_id=1`, result `created`, successful shard `1`, failed shard `0`.
- Search: `hits.total.value=1`.

```json
{
  "message": "hello from non-bitnami image test",
  "source": "eck",
  "stack_version": "8.19.21"
}
```

Gerçek search çıktısı sunucuda `artifacts/2026-09-04/search-result.json` altında toplandı.
