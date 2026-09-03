# Contabo Kurulum ve Test Runbook

## 1. Sunucu ön kontrolü

```bash
uname -m
lsb_release -a
lscpu
free -h
df -h
ps aux --sort=-%mem | head -20
systemctl --type=service --state=running
```

Devam koşulları: Ubuntu amd64/x86_64, swap kapalı, en az 4 GiB available RAM (tercihen 5 GiB), en az 30 GiB boş disk ve çalışan SSH erişimi. Script firewall değiştirmez ve mevcut servisleri durdurmaz. Gereksiz servisleri çıktı üzerinden kendiniz değerlendirin.

## 2. Repository ve K3s

```bash
git clone https://github.com/AhmettDgn/elasticsearch-kibana-bitnami-image-research.git
cd elasticsearch-kibana-bitnami-image-research
sudo ./scripts/bootstrap-k3s.sh
```

```bash
sudo sysctl vm.max_map_count
kubectl get nodes -o wide
kubectl get storageclass
kubectl get pods -A
```

Beklenen: node `Ready`, `local-path` mevcut ve `vm.max_map_count = 262144`. K3s Traefik kurulmaz. Bootstrap, root kubeconfig'i dünyaya okunabilir yapmak yerine sudo kullanan kullanıcı için `~/.kube/config` altında mode `0600` kopya oluşturur.

## 3. Deployment

```bash
./scripts/deploy.sh
```

```bash
kubectl get pods -n elastic-system
kubectl get elasticsearch,kibana,pods,pvc,svc -n elastic-stack
```

Beklenen: ECK operator, Elasticsearch, Kibana ve exporter Ready; PVC Bound; uygulama servisleri ClusterIP.

## 4. Parolayı yalnız gerektiğinde görüntüleme

Bu komut çıktısını kaydetmeyin veya screenshot almayın:

```bash
kubectl -n elastic-stack get secret elastic-stack-es-elastic-user -o go-template='{{.data.elastic | base64decode}}{{"\n"}}'
```

## 5. SSH tüneli

Sunucuda iki terminal:

```bash
kubectl -n elastic-stack port-forward service/elastic-stack-kb-http 5601:5601 --address 127.0.0.1
```

```bash
kubectl -n elastic-stack port-forward service/elastic-stack-es-http 9200:9200 --address 127.0.0.1
```

Laptop'ta:

```bash
ssh -L 5601:127.0.0.1:5601 -L 9200:127.0.0.1:9200 ubuntu@SUNUCU_IP
```

Kibana: `https://localhost:5601`. ECK self-signed sertifikası nedeniyle tarayıcı uyarısı beklenir.

## 6. Test ve kanıt

```bash
./tests/static/run.sh
./scripts/verify.sh
./scripts/collect-evidence.sh
```

Kontrollü pod recreation ve persistence testi:

```bash
./tests/resilience/run.sh
./scripts/collect-evidence.sh
```

`artifacts/YYYY-MM-DD` altındaki temizlenmiş çıktıları inceleyin. Screenshot listesini `screenshots/README.md` dosyasından takip edin.

## 7. Sorun giderme

```bash
kubectl describe elasticsearch elastic-stack -n elastic-stack
kubectl describe kibana elastic-stack -n elastic-stack
kubectl logs -n elastic-system statefulset/elastic-operator --tail=200
kubectl get events -n elastic-stack --sort-by=.lastTimestamp
free -h
df -h
```

Parola, token veya Secret içeriğini issue/rapor içine yapıştırmayın.
