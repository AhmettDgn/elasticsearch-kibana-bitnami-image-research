# Metrics Exporter Testi

Exporter, Prometheus Community `v1.11.0` image'ını kullanır. Kullanıcı/parola Kubernetes Secret'tan, CA ise ECK public certificate Secret'ından mount edilir.

`scripts/verify.sh`, `/metrics` altında `elasticsearch_` prefix'li metrik bulunduğunu doğrular. Kanıt dosyası yalnız Elasticsearch metrik satırlarını içerir; credentials veya Authorization header içermez.

## ECK TLS/SAN davranışı

Port-forward loopback üzerinde dinlese de HTTPS hostname olarak `127.0.0.1` kullanılmaz. Script, ECK sertifikasındaki geçerli SAN olan `elastic-stack-es-http.elastic-stack.svc` adını kullanır ve configurable local portu `--resolve <service-dns>:<port>:127.0.0.1` ile port-forward'a yönlendirir. ECK public HTTP CA Secret'ı doğrulamada kalır; `-k`/`--insecure` kullanılmaz.

API probe her denemede port-forward process'inin yaşadığını kontrol eder. Curl hatası retry sırasında görünürdür; timeout halinde son curl hatası ve `port-forward.log` cleanup öncesinde stderr'e basılır. Regression testi başarılı bağlantı, retry ve timeout diagnostics senaryolarını kapsar.
