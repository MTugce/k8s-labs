# Prometheus ve Grafana ile Cluster ve Uygulama Metriklerini İzle

## Amaç

Cluster ve uygulama metriklerini Prometheus ile toplamak, Grafana'da izlemek ve alert üretmek.

## Kullanılan Kubernetes nesneleri

- **ServiceMonitor:** Prometheus'a hangi Service'ten metrik toplayacağını söyler.
- **PrometheusRule:** PromQL ifadesiyle alert koşulunu tanımlar.
- **ConfigMap:** Grafana dashboard JSON dosyasını taşır.
- **Secret:** Grafana yönetici giriş bilgisini saklar.

## Çalışma dizini

```bash
cd ~/k8s-labs/lab-10-prometheus-grafana-monitoring
```

Bu labın sonunda **Prometheus ve Grafana silinmez**. Sonraki monitoring dersinde aynı kurulum kullanılacaktır.

## 1. Uygulamanın ve HPA'nın hazır olduğunu doğrula

```bash
kubectl -n private-app get deployment,pods,service,hpa
kubectl top pods -n private-app
```

Beklenen sonuç: `devops-app` Pod'ları çalışır ve Metrics Server CPU değerleri gösterir.

`private-app` namespace'i, `devops-app` Deployment'ı veya HPA görünmüyorsa bu labda ilerleme. Önce Lab 2'yi ve HPA için Lab 7'yi tamamla.

## 2. Grafana yönetici Secret'ını yerelde oluştur

Gerçek kullanıcı adı veya parola repoda tutulmaz. `stringData` kullanan şablonu yerel dosyaya kopyala ve kendi lab değerlerini yaz.

```bash
cp ~/k8s-labs/lab-10-prometheus-grafana-monitoring/starter/grafana-admin-secret.example.yaml grafana-admin.local.yaml
nano grafana-admin.local.yaml
kubectl create namespace monitoring
kubectl apply -n monitoring -f grafana-admin.local.yaml
kubectl -n monitoring get secret grafana-admin
```

Beklenen sonuç: yalnızca `grafana-admin` Secret adı görünür; parola terminale yazdırılmaz.

## 3. Monitoring chart repository'sini ekle

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm search repo prometheus-community/kube-prometheus-stack
```

Beklenen sonuç: `kube-prometheus-stack` chart adı ve sürümü görünür.

## 4. Prometheus ve Grafana'yı Helm ile kur

`monitoring-values.yaml`, Grafana'yı NodePort `30089` ile açar; Prometheus ve Grafana için local-path PVC ister. Ayrıca Prometheus'un farklı namespace'lerdeki ServiceMonitor ve PrometheusRule kaynaklarını okuyabilmesini sağlar.

```bash
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --version 91.5.0 \
  --namespace monitoring \
  --values ~/k8s-labs/lab-10-prometheus-grafana-monitoring/starter/monitoring-values.yaml \
  --wait
helm list -n monitoring
kubectl -n monitoring get pods,service,pvc
```

Beklenen sonuç: Prometheus, Grafana ve Alertmanager Pod'ları `Running` olur. Grafana Service'inde `30089` NodePort görünür.

## 5. Uygulamayı `/metrics` endpoint'iyle yeniden yayınla

Bu repodaki `devops-app` artık HTTP istek sayısı, istek süresi ve Node.js process metrikleri üretir. Image'i yeni tag ile üretip private registry'ye gönder.

```bash
export DOCKERHUB_USER="KENDI_DOCKERHUB_KULLANICI_ADIN"
export METRICS_IMAGE="docker.io/${DOCKERHUB_USER}/devops-app:1.1"
docker build -t "$METRICS_IMAGE" ~/k8s-labs/app/devops-app
docker push "$METRICS_IMAGE"
kubectl -n private-app set image deployment/devops-app devops-app="$METRICS_IMAGE"
kubectl -n private-app rollout status deployment/devops-app
curl http://SUNUCU_IP:30087/metrics | head
```

Beklenen sonuç: son komutta `devops_app_http_requests_total` ve `process_` ile başlayan metrik adları görünür.

## 6. Dashboard, rapor ve alert kaynaklarını ekle

Bu script ServiceMonitor'u, iki Grafana dashboard'unu ve üç alert kuralını ekler.
Grafana sidecar'ı, `grafana_dashboard=1` etiketli ConfigMap'leri otomatik yükler.

```bash
bash ~/k8s-labs/lab-10-prometheus-grafana-monitoring/scripts/apply-observability-assets.sh
```

Beklenen sonuç: `devops-app` ServiceMonitor'u, `devops-app-alerts` PrometheusRule'u
ve iki dashboard ConfigMap'i görünür. Prometheus'un hedefi bulması kısa sürebilir.

## 7. Grafana dashboard'larını aç ve manuel import yap

Tarayıcıda `http://SUNUCU_IP:30089` adresini aç. İkinci adımda yazdığın Grafana kullanıcı bilgileriyle giriş yap. Sol menüden **Dashboards** altında `Devops App Lab` dashboard'unu aç.

Beklenen sonuç: `Devops App Lab` ve `Devops App Operations` dashboard'larında istek
hızı, p95 süre, HPA replica sayısı ve hedef durumu görünür. Kube Prometheus Stack'in
hazır Kubernetes dashboard'ları da listelenir.

Başka bir dashboard'u manuel eklemek için **Dashboards → New → Import** yolunu aç.
Grafana.com dashboard URL/ID'sini veya JSON dosyasını gir, veri kaynağı olarak
`Prometheus` seç ve **Import** düğmesine bas. Dashboard seçmek için
[Grafana dashboard kataloğunu](https://grafana.com/grafana/dashboards/) kullan;
adımların resmî karşılığı [Grafana import rehberinde](https://grafana.com/docs/grafana/latest/visualizations/dashboards/build-dashboards/import-dashboards/) bulunur.

## 8. Kontrollü yük üret ve alert oluştur

Önce scriptin ne yaptığını oku: private-app namespace'inde geçici bir curl Pod'u oluşturur ve `/work?ms=500` endpoint'ine sürekli istek gönderir.

```bash
sed -n '1,120p' ~/k8s-labs/lab-10-prometheus-grafana-monitoring/scripts/run-load-test.sh
bash ~/k8s-labs/lab-10-prometheus-grafana-monitoring/scripts/run-load-test.sh
```

Başka terminalde aşağıdakileri izle.

```bash
kubectl -n private-app get hpa,pods -w
kubectl -n monitoring get pods
```

Yaklaşık iki dakika sonra Grafana dashboard'unda istek süresi yükselir. PrometheusRule'daki `DevopsAppSlowRequests` alert'i `Firing` durumuna geçer; Grafana Alerting ekranında veya Prometheus Alerts ekranında görünür.

Bu yük ayrıca HPA üst sınıra uzun süre ulaşırsa `DevopsAppHpaAtMaximum` alert'ini
de üretir. `DevopsAppTargetDown` ise Prometheus uygulama hedefinden veri alamazsa
çalışır.

## 9. Metin raporunu al, yükü durdur; monitoring platformunu bırak

Bu script Prometheus API'den hedef durumu, istek hızı, p95 süre, HPA replica
sayısı ve firing alertleri yazdırır. Rapor için geçici yerel `19090` portu kullanır.

```bash
bash ~/k8s-labs/lab-10-prometheus-grafana-monitoring/scripts/monitoring-report.sh
bash ~/k8s-labs/lab-10-prometheus-grafana-monitoring/scripts/stop-load-test.sh
kubectl -n private-app get hpa
helm status monitoring -n monitoring
```

Beklenen sonuç: HPA zamanla minimum replica değerine iner. `monitoring` release'i `deployed` kalır. Bu labda Prometheus/Grafana'yı kaldırma.
