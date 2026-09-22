# Eğitim Akışı

Her bölüm aynı ritimle ilerler: 15-20 dakika konu anlatımı, 35-60 dakika lab, gerçek komutla doğrulama.

| Sıra | Sunum konusu | Uygulama çıktısı |
| --- | --- | --- |
| 1 | Kind ve kubectl | Üç node, imperatif Pod komutları |
| 2 | Pod, Deployment, Service | Self-healing, scale, ClusterIP/NodePort/ExternalName/LoadBalancer |
| 3 | İmaj, ConfigMap, Secret | Private Docker Hub imajını `imagePullSecrets` ile çalıştırma |
| 4 | NGINX Ingress | App1 DNS slotundan ClusterIP Service'e erişim |
| 5 | Gateway API | HTTPRoute preview ve altyapıyı değiştirmeden geçiş |
| 6 | PV, PVC, StorageClass | Static HostPath ve dynamic local storage |
| 7 | NFS ve StatefulSet | RWX NFS PVC, MySQL kimliği ve kalıcılık |
| 8 | DaemonSet ve HPA | Her node'da ajan, CPU yüküyle scale-out/scale-in |
| 9 | Deployment stratejileri | Recreate, Rolling, Blue-Green, Canary ve rollback |
| 10 | Helm release yönetimi | WordPress ile repository, install, upgrade, rollback ve uninstall |
| 11 | Prometheus ve Grafana | Cluster/Pod/uygulama metrikleri, dashboard, alert ve kontrollü yük |
| 12 | Kaynak yönetimi | LimitRange varsayılanı ve ResourceQuota reddi |
| 13 | RBAC | ServiceAccount, Role, RoleBinding ve izin doğrulama |

Tekrarlayan lab yoktur: her yeni bölüm önceki labdaki `devops-app` uygulamasına bir Kubernetes yeteneği ekler. WordPress yalnızca geçici Helm release örneğidir; Prometheus ve Grafana monitoring dersi için cluster'da bırakılır. `cheat-sheets/` klasörü ders sırasında komut hatırlatıcı olarak kullanılır; lab dosyaları ise yalnızca gerekli adımları içerir.
