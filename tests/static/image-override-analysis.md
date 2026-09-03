# Yalnız Image Override Deneyi

`helm-values/image-override-only.yaml`, legacy chart'ta Elasticsearch ve Kibana repository değerlerini resmi image'lara çevirir; metrics, sysctl ve volume helper pod'larını kapatır.

Bu override deploy amaçlı değildir. Legacy render hâlâ Bitnami environment değişkenleri, `/opt/bitnami` healthcheck/config yolları ve `/bitnami` volume mount'ları üretir. Sonuç: image override, container runtime sözleşmesini uyarlamadığı için yeterli değildir.

## Yerel render sonucu — 2026-09-03

Helm `v3.18.6` ile legacy values ve image override birlikte render edildi. Çıktıda `/opt/bitnami` veya `/bitnami/` içeren 15 runtime path satırı kaldı. Bunların içinde Kibana PID/config/data mount yolları ile Elasticsearch healthcheck ve data mount yolları bulunuyor.
