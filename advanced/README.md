# Advanced Kubernetes Labları

Bu bölüm birden fazla controller ve operasyonel bileşen içeren ileri seviye çalışmalar içindir. İki günlük temel eğitimin zorunlu parçası değildir.

| Sıra | Lab | Süre | Öğrenme hedefi |
|---:|---|---:|---|
| 1 | [Gateway API](lab-01-gateway-api/README.md) | 60–75 dk | Ingress'ten rol tabanlı Gateway API'ye geçiş |
| 2 | [NFS ve StatefulSet](lab-02-nfs-and-statefulset/README.md) | 70–90 dk | RWX storage ve durum bilgili workload |
| 3 | [Blue-Green ve Canary](lab-03-blue-green-and-canary/README.md) | 75–100 dk | İleri yayın stratejileri |
| 4 | [Helm Operasyonları](lab-04-helm-operations/README.md) | 60–75 dk | Install, upgrade, rollback ve uninstall |
| 5 | [Prometheus ve Grafana](lab-05-prometheus-grafana/README.md) | 90–120 dk | Metrik, dashboard ve alarm yönetimi |
| 6 | [Headlamp Dashboard](lab-06-headlamp-cluster-dashboard/README.md) | 45–60 dk | Salt-okunur görsel cluster yönetimi |
| 7 | [Scheduling ve Node Bakımı](lab-07-scheduling-and-node-maintenance/README.md) | 50–65 dk | nodeSelector, taint, toleration ve drain |

## Önerilen sıra

Gateway API labı Intermediate Ingress labının; Blue-Green ve Canary labı Intermediate RollingUpdate labının devamıdır. Diğer lablar ihtiyaca göre bağımsız seçilebilir.

[Ana sayfaya dön](../README.md)
