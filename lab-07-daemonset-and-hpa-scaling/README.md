# * Her Node'da Ajan Çalıştır ve Uygulamanı Otomatik Ölçekle

## Amaç

DaemonSet ile her node üzerinde zorunlu ajan Pod'u çalıştırmayı ve Horizontal Pod Autoscaler (HPA) ile gelen CPU yüküne göre Deployment'ı dinamik olarak otomatik ölçeklemeyi (scale-out / scale-in) öğrenmek.

## Kullanılan Kubernetes nesneleri

- **DaemonSet:** Kümedeki her node (control-plane dahil) üzerinde tam birer kopya Pod çalıştırır.
- **HPA (HorizontalPodAutoscaler):** CPU/Bellek metriklerini izleyerek Deployment pod sayısını otomatik artırıp azaltır.
- **Metrics Server:** Pod ve node'ların anlık CPU/RAM kullanımını toplayan Kubernetes metriği eklentisidir.

## Çalışma dizini

```bash
cd ~/k8s-labs/lab-07-daemonset-and-hpa-scaling
```

## * Doğrulanan senaryo

DaemonSet kümedeki 3 node'un her birine birer Pod yerleştirdi. Üretilen suni CPU yükü ile HPA hedef eşiği aşıldı ve `devops-app` replica sayısı 1'den 6'ya çıktı. Yük kesildiğinde HPA pod sayısını tekrar 1'e indirdi.

---

## 1. Metrics Server Kurulumu

HPA'nın pod'ları ölçekleyebilmesi için kümede Metrics Server çalışıyor olmalıdır:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.7.2/components.yaml

kubectl -n kube-system patch deployment metrics-server --type=json \
  --patch-file starter/metrics-server-kind-patch.json

kubectl wait -n kube-system --for=condition=Available deployment/metrics-server --timeout=180s
```

Metriklerin toplanmaya başladığını doğrula:

```bash
kubectl top nodes
kubectl top pods -n private-app
```

Beklenen sonuç: Node'lar ve Pod'lar için anlık CPU ve bellek (Mi) değerleri listelenir.

---

## 2. DaemonSet ile Her Node'da Ajan Çalıştır

Aşağıdaki manifest (`starter/daemonset.yaml`), control-plane dahil kümedeki her node'a birer `node-label-agent` Pod'u dağıtır:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-label-agent
  namespace: private-app
spec:
  selector:
    matchLabels:
      app: node-label-agent
  template:
    metadata:
      labels:
        app: node-label-agent
    spec:
      tolerations:
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
          effect: NoSchedule
      containers:
        - name: agent
          image: busybox:1.37
          command:
            - sh
            - -c
            - "echo running-on-$(hostname); sleep 3600"
```

DaemonSet'i uygula:

```bash
kubectl apply -f starter/daemonset.yaml
kubectl -n private-app get daemonset node-label-agent
kubectl -n private-app get pods -l app=node-label-agent -o wide
```

Beklenen sonuç: 3 adet node olduğu için `DESIRED: 3, CURRENT: 3, READY: 3` olur ve her Pod farklı bir node üzerinde çalışır.

---

## 3. HPA (Horizontal Pod Autoscaler) Tanımla

Aşağıdaki manifest (`starter/hpa.yaml`), `devops-app` Deployment'ının ortalama CPU kullanımı %50'yi aştığında pod sayısını en fazla 6'ya kadar otomatik artıracak kuralı tanımlar:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: devops-app
  namespace: private-app
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: devops-app
  minReplicas: 1
  maxReplicas: 6
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 30
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 50
```

HPA kaynağını cluster'a uygula:

```bash
kubectl apply -f starter/hpa.yaml
kubectl -n private-app get hpa devops-app
```

Beklenen sonuç: `devops-app` HPA'sı hedef olarak `cpu: 0%/50%` ve `MINPODS: 1, MAXPODS: 6` olarak listelenir.

---

## 4. Yük Üreticiyi Başlat ve Otomatik Ölçeklemeyi İzle

Aşağıdaki pod (`starter/load-generator.yaml`), uygulamaya sürekli istek göndererek CPU kullanımını yükseltir:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: load-generator
  namespace: private-app
spec:
  restartPolicy: Never
  containers:
    - name: curl
      image: curlimages/curl:8.12.1
      command:
        - sh
        - -c
      args:
        - while true; do curl -s http://devops-app/work?ms=500 >/dev/null; done
```

Yük üreticiyi başlat:

```bash
kubectl apply -f starter/load-generator.yaml
```

HPA'nın pod sayısını artırmasını (scale-out) canlı izle:

```bash
kubectl -n private-app get hpa,pods -l app=devops-app -w
```

Beklenen sonuç: CPU kullanımı %50 eşiğini aşar ve HPA yeni Pod'lar ekleyerek replica sayısını 1'den 2, 4, 6'ya kadar çıkarır. `Ctrl+C` ile izlemeyi sonlandırın.

---

## 5. Yükü Durdur ve Küçülmeyi (Scale-in) Gör

Yük üretici pod'u silerek trafiği kesin:

```bash
kubectl -n private-app delete pod load-generator
```

Soğuma süresinin (stabilization window) ardından pod sayısının tekrar minimuma düşmesini izle:

```bash
kubectl -n private-app get hpa,pods -l app=devops-app -w
```

Beklenen sonuç: CPU kullanımı %0'a düşer ve HPA pod sayısını güvenle tekrar 1'e indirir.
