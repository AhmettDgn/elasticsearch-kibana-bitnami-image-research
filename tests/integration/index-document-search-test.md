# Index, Document ve Search Testi

Test akışı:

1. `bitnami-free-demo` index'i `number_of_replicas: 0` ile oluşturulur.
2. Sabit ID'li örnek document `refresh=wait_for` ile eklenir.
3. `_search?q=_id:1` çağrısında beklenen mesaj doğrulanır.

Gerçek çıktı `artifacts/YYYY-MM-DD/search-result.json` altında toplanacaktır.
