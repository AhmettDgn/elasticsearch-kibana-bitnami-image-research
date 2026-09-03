# Metrics Exporter Testi

Exporter, Prometheus Community `v1.11.0` image'ını kullanır. Kullanıcı/parola Kubernetes Secret'tan, CA ise ECK public certificate Secret'ından mount edilir.

## Numeric UID/GID doğrulaması

[Upstream `v1.11.0` Dockerfile](https://github.com/prometheus-community/elasticsearch_exporter/blob/v1.11.0/Dockerfile), final image için `quay.io/prometheus/busybox-linux-amd64:glibc` tabanını ve isim tabanlı `USER nobody` değerini kullanır. Yayınlanmış `ghcr.io/prometheus-community/elasticsearch-exporter:v1.11.0` linux/amd64 manifesti (`sha256:54c6d05ae745c12643501b2b056474faab530ad4b963ff2bceecc6aefc650869`) ayrıca incelendi:

- Image config: `User=nobody`.
- Image katmanındaki `/etc/passwd`: `nobody:x:65534:65534:nobody:/home:/bin/false`.
- Image katmanındaki `/etc/group`: `nobody:x:65534:`.

Bu nedenle varsayılan exporter container securityContext değeri `runAsUser: 65534` ve `runAsGroup: 65534` olarak tanımlandı. Değerler `exporter.containerSecurityContext` üzerinden değiştirilebilir. `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, salt-okunur root filesystem, tüm capability'lerin kaldırılması ve `RuntimeDefault` seccomp korunur.

`scripts/verify.sh`, önce `/healthz` endpoint'ini, ardından `/metrics` altında `elasticsearch_` prefix'li metrik bulunduğunu doğrular. Kanıt dosyası yalnız Elasticsearch metrik satırlarını içerir; credentials veya Authorization header içermez.

## ECK TLS/SAN davranışı

Port-forward loopback üzerinde dinlese de HTTPS hostname olarak `127.0.0.1` kullanılmaz. Script, ECK sertifikasındaki geçerli SAN olan `elastic-stack-es-http.elastic-stack.svc` adını kullanır ve configurable local portu `--resolve <service-dns>:<port>:127.0.0.1` ile port-forward'a yönlendirir. ECK public HTTP CA Secret'ı doğrulamada kalır; `-k`/`--insecure` kullanılmaz.

API probe her denemede port-forward process'inin yaşadığını kontrol eder. Curl hatası retry sırasında görünürdür; timeout halinde son curl hatası ve `port-forward.log` cleanup öncesinde stderr'e basılır. Regression testi başarılı bağlantı, retry ve timeout diagnostics senaryolarını kapsar.

Varsayılan `LOCAL_PORT=19200` değeridir. Script port-forward başlatmadan önce portun dinlemede olup olmadığını kontrol eder; doluysa anlaşılır bir hata ile durur ve örneğin `LOCAL_PORT=19443` seçilmesini önerir.
