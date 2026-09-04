# Kibana Testi

`scripts/verify.sh`, ECK Kibana CA sertifikası ve authentication kullanarak `/api/status` endpoint'inin `available` durumunu doğrular. Görsel erişim SSH tüneli üzerinden kullanıcı tarafından test edilir.

## Gerçek Contabo sonucu — 2026-09-04

- Kibana version: `8.19.21`.
- Health: `green`.
- Node/pod: `1`, pod `1/1 Running`.
- `/api/status`: `overall.level=available`.

Gerçek API çıktısı sunucuda `artifacts/2026-09-04/kibana-status.json` altında toplandı. Screenshot alınırken kullanıcı adı, parola ve token görüntülenmemelidir.
