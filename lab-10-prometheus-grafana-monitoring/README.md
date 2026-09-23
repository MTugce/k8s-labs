# Prometheus ve Grafana ile Cluster ve Uygulama Metriklerini İzle

## Amaç

Cluster ve uygulama metriklerini Prometheus ile toplamak, Grafana üzerinde görsel panellerle izlemek ve alert kuralları tetiklemek.

## Kullanılan Kubernetes nesneleri

- **ServiceMonitor:** Prometheus Operator'a hangi Service'ten metrik toplanacağını bildirir.
- **PrometheusRule:** PromQL ifadeleriyle eşik değer aşıldığında üretilecek alert koşullarını tanımlar.
- **ConfigMap:** Grafana dashboard JSON tanımlarını taşır (`grafana_dashboard=1`).
- **Secret:** Grafana yönetici giriş bilgilerini (`admin-user`, `admin-password`) saklar.

## Çalışma dizini

```bash
cd ~/k8s-labs/lab-10-prometheus-grafana-monitoring
```

## Monitoring mimarisi

```text
devops-app /metrics → Service → ServiceMonitor → Prometheus Operator → Prometheus
                                                                    ├→ Grafana Dashboard
                                                                    └→ PrometheusRule → Alertmanager
```

---

## 1. Uygulamanın ve HPA'nın hazır olduğunu doğrula

```bash
kubectl -n private-app get deployment,pods,service,hpa
kubectl top pods -n private-app
```

Beklenen sonuç: `devops-app` Pod'ları çalışır ve Metrics Server CPU değerleri listelenir.

---

## 2. Grafana Yönetici Giriş Secret'ını Hazırla

Aşağıdaki manifest (`starter/grafana-admin-secret.example.yaml`), Grafana yönetici panelinin kullanıcı adı ve parolasını belirler:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: grafana-admin
type: Opaque
stringData:
  admin-user: "__YEREL_GRAFANA_KULLANICI_ADI__"
  admin-password: "__YEREL_GRAFANA_PAROLASI__"
```

Dosyayı kopyala, `sed` ile kullanıcı ve parola bilgilerini yerleştirip `monitoring` namespace'ine uygula:

```bash
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

cp starter/grafana-admin-secret.example.yaml grafana-admin.local.yaml
sed -i "s|__YEREL_GRAFANA_KULLANICI_ADI__|admin|g; s|__YEREL_GRAFANA_PAROLASI__|student-lab-monitor|g" grafana-admin.local.yaml
kubectl apply -n monitoring -f grafana-admin.local.yaml

kubectl -n monitoring get secret grafana-admin
```

---

## 3. Monitoring Helm Deposunu Ekle ve Güncelle

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

---

## 4. Kube Prometheus Stack'i Kur

Grafana'yı ayrılmış `30089` NodePort portunda açan ve diğer namespace'lerdeki ServiceMonitor'leri okumasını sağlayan `starter/monitoring-values.yaml` ile kurulumu yap:

```bash
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --version 91.5.0 \
  --namespace monitoring \
  --values starter/monitoring-values.yaml \
  --wait
```

Kurulan bileşenleri doğrula:

```bash
kubectl -n monitoring get pods,service,pvc
```

Beklenen sonuç: Prometheus, Grafana ve Alertmanager Pod'ları `Running` olur. Grafana servisinde `30089` NodePort portu görünür.

---

## 5. ServiceMonitor, Dashboard ve Alert Kaynaklarını Ekle

Aşağıdaki ServiceMonitor (`starter/devops-app-servicemonitor.yaml`), Prometheus'un `private-app` namespace'indeki `devops-app` servisinin `/metrics` ucunu her 15 saniyede bir kazımasını (scrape) sağlar:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: devops-app
  namespace: private-app
  labels:
    release: monitoring
spec:
  selector:
    matchLabels:
      app: devops-app
  endpoints:
    - port: http
      path: /metrics
      interval: 15s
```

Tüm izleme ve dashboard varlıklarını uygulayan scripti çalıştır:

```bash
bash scripts/apply-observability-assets.sh
```

Beklenen sonuç: `devops-app` ServiceMonitor'u, `devops-app-alerts` PrometheusRule'u ve dashboard ConfigMap'leri cluster'a yüklenir.

---

## 6. Grafana Paneline Giriş Yap ve İncele

- **Grafana URL:** `http://SUNUCU_IP:30089` (veya port-forward / yerel erişimde `http://127.0.0.1:30089`)
- **Kullanıcı adı:** `admin`
- **Parola:** `student-lab-monitor`

Giriş yaptıktan sonra sol menüden **Dashboards** sekmesine gidin. `Devops App Lab` ve `Devops App Operations` panellerini açarak istek hızı, p95 gecikme süresi ve HPA pod metriklerini izleyin.

---

## 7. Yük Üret ve Alert Tetikle

Uygulamanın `/work?ms=500` endpoint'ine sürekli istek göndererek gecikme süresini yükselt:

```bash
bash scripts/run-load-test.sh
```

Başka bir terminalde Pod ve HPA tepkisini izleyin:

```bash
kubectl -n private-app get hpa,pods -w
```

Grafana Alerting sekmesinde `DevopsAppSlowRequests` kuralının yeşilden sarıya (`Pending`) ve ardından kırmızıya (`Firing`) geçtiğini gözlemleyin.

---

## 8. Metin Raporunu Al ve Yükü Durdur

İzleme metriklerinin terminal özetini alıp yük testini sonlandırın:

```bash
bash scripts/monitoring-report.sh
bash scripts/stop-load-test.sh
```

> [!NOTE]
> Bu labın sonunda Prometheus ve Grafana kaldırılmaz; sonraki izleme pratiklerinde kullanılmak üzere çalışır durumda bırakılır.
