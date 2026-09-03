# Persistence ve Idempotency Testi

`tests/resilience/run.sh`:

1. Deployment'ı ikinci kez çalıştırır.
2. Integration testini geçirir.
3. Elasticsearch pod'unu kontrollü siler.
4. ECK tarafından yeniden oluşturulan pod'un Ready olmasını bekler.
5. Aynı document'i tekrar arayarak PVC persistence'ı doğrular.

Bu test pod restart süresince kesinti oluşturur ve yalnız lab ortamında çalıştırılmalıdır.
