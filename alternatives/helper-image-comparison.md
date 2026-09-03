# Helper ve Init Image Alternatifleri

| Aday | Shell araçları | Permissions | Sysctl | Sonuç |
|---|---|---|---|---|
| Bitnami shell/os-shell | Geniş | Legacy scriptlerle uyumlu | Uyumlu | Aktif sistemden kaldırıldı |
| BusyBox | Temel | Basit `chown` için yeterli | Privileged çalışabilir | Image gerektirmeyen çözüm tercih edildi |
| Alpine | Paketlenebilir | Uygun | Privileged çalışabilir | Gereksiz ek attack surface |
| UBI minimal | Kurumsal taban | Uygun | Privileged çalışabilir | Bu lab için gereksiz |
| Wolfi shell | Minimal | Araç setine bağlı | Privileged çalışabilir | Bu lab için gereksiz |

Seçilen yaklaşım helper image kullanmaz. `vm.max_map_count` Ubuntu host üzerinde kalıcı ayarlanır; volume izinleri `local-path`, `fsGroup` ve container security context ile yönetilir.
