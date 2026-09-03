# Persistence ve Idempotency Testi

`tests/resilience/run.sh`:

1. Deployment'ı ikinci kez çalıştırır.
2. Integration testini geçirir.
3. Elasticsearch pod'unu kontrollü siler.
4. ECK tarafından yeniden oluşturulan pod'un Ready olmasını bekler.
5. Aynı document'i tekrar arayarak PVC persistence'ı doğrular.

Bu test pod restart süresince kesinti oluşturur ve yalnız lab ortamında çalıştırılmalıdır.

Test, silme işleminden önce `demo-index/_doc/1` belgesinin `found=true` olduğunu doğrular. Pod silindikten sonra selector altında yeni UID'li pod görünene kadar poll yapılır; resource oluşmadan `kubectl wait` çağrılmaz. Yeni pod Ready olduktan sonra Elasticsearch CR'ın tekrar `phase=Ready` ve `health=green` olması, API'nin erişilebilir hale gelmesi ve aynı belgenin yeniden `found=true` dönmesi beklenir.

Timeout veya beklenmeyen hata durumunda Elasticsearch, pod, PVC, event ve Elasticsearch CR describe diagnostics çıktıları otomatik yazdırılır. `INDEX_NAME`, timeout ve retry değerleri environment variable ile değiştirilebilir.
