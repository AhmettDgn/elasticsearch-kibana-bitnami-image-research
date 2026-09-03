# Metrics Exporter Testi

Exporter, Prometheus Community `v1.11.0` image'ını kullanır. Kullanıcı/parola Kubernetes Secret'tan, CA ise ECK public certificate Secret'ından mount edilir.

`scripts/verify.sh`, `/metrics` altında `elasticsearch_` prefix'li metrik bulunduğunu doğrular. Kanıt dosyası yalnız Elasticsearch metrik satırlarını içerir; credentials veya Authorization header içermez.
