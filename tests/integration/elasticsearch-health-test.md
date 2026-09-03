# Elasticsearch Health Testi

`scripts/verify.sh`, ECK CA ve yönetilen kullanıcıyla TLS üzerinden `_cluster/health` çağrısı yapar. Tek node test index'inde replica sayısı sıfır olduğu için beklenen durum `green`'dir.

Gerçek çıktı `artifacts/YYYY-MM-DD/cluster-health.json` altında toplanacaktır.
