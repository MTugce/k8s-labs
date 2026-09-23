# * Sürümü Güvenle Yayınla: Recreate, Rolling, Blue-Green ve Canary

## Amaç

Modern yazılım dağıtım stratejileri olan Recreate, RollingUpdate, Blue-Green ve Canary mimarilerini; **uygulamaya içeriden `curl` istekleri göndererek canlı trafik davranışını (kesinti anı, sıfır kesinti, anlık geçiş ve yüzdelik dağılım)** uygulamalı olarak öğrenmek.

## Kullanılan Kubernetes nesneleri

- **Deployment:** Recreate ve RollingUpdate stratejileri ile pod güncellemelerini yönetir.
- **Service:** Blue-Green stratejisinde pod label selector'ını anlık değiştirerek canlı trafiği yeni sürüme aktarır.
- **Gateway & HTTPRoute:** Canary stratejisinde gelen HTTP trafiğini sürümler arasında yüzdelik oranlarla (%90-%10, %50-%50) paylaştırır.

## Çalışma dizini

```bash
cd ~/k8s-labs/lab-08-deployment-strategies
```

---

## 1. İkinci İmaj Sürümünü Derle ve Test İstemcisini Hazırla

Canlı güncelleme stratejilerini deneyebilmek için iki farklı sürüme (`1.0` ve `2.0`) ihtiyacımız var.

Değişkenleri tanımla:

```bash
export DOCKERHUB_USER="KENDI_DOCKERHUB_KULLANICI_ADIN"
export IMAGE="docker.io/${DOCKERHUB_USER}/devops-app"
export STUDENT_ID="${STUDENT_ID:-$(hostname)}"
export APP_HOST="${STUDENT_ID}-app1.devopsatolyesi.com"
```

İkinci imajı (`2.0`) derleyip Docker Hub'a gönder:

```bash
docker build --build-arg APP_VERSION=2.0 -t "${IMAGE}:2.0" ~/k8s-labs/app/devops-app
docker push "${IMAGE}:2.0"
```

Kubernetes'in private Docker Hub imajlarını çekebilmesi için ServiceAccount yetkisini tanımla ve cluster içinden canlı istek gönderecek `test-client` Pod'unu başlat:

```bash
kubectl create namespace private-app --dry-run=client -o yaml | kubectl apply -f -
kubectl -n private-app patch serviceaccount default -p '{"imagePullSecrets": [{"name": "dockerhub-creds"}]}' 2>/dev/null || true

kubectl -n private-app run test-client --image=curlimages/curl:8.12.1 --restart=Never -- sleep 3600
kubectl -n private-app wait --for=condition=Ready pod/test-client --timeout=60s
```

---

## 2. Recreate Stratejisi — Kesinti Anını (Downtime) Canlı Gör

Recreate stratejisinde Kubernetes, yeni sürüm pod'larını başlatmadan önce mevcut tüm eski pod'ları sonlandırır. Bu durum servis kesintisine yol açar.

Aşağıdaki manifest (`starter/recreate.yaml`), Recreate stratejisi kullanan 2 replikalı bir Deployment ve Service tanımlar:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: devops-app-recreate
  namespace: private-app
spec:
  replicas: 2
  strategy:
    type: Recreate                  # Önce eskileri tamamen kapat, sonra yenileri aç
  selector:
    matchLabels:
      app: devops-app-recreate
  template:
    metadata:
      labels:
        app: devops-app-recreate
    spec:
      containers:
        - name: app
          image: __IMAGE__:1.0
          ports:
            - containerPort: 8080
              name: http
---
apiVersion: v1
kind: Service
metadata:
  name: strategy-recreate
  namespace: private-app
spec:
  selector:
    app: devops-app-recreate
  ports:
    - name: http
      port: 80
      targetPort: 8080
```

Manifesti imaj adınla cluster'a uygula:

```bash
sed "s|__IMAGE__|${IMAGE}|g" starter/recreate.yaml | kubectl apply -f -
kubectl -n private-app rollout status deployment/devops-app-recreate
```

Uygulamanın `1.0` sürümünde çalıştığını doğrula:

```bash
kubectl -n private-app exec test-client -- curl -s http://strategy-recreate/
```

Beklenen sonuç: `{"application":"devops-app","version":"1.0","pod":"devops-app-recreate-..."}` döner.

Şimdi imajı `2.0` sürümüne güncelle:

```bash
kubectl -n private-app set image deployment/devops-app-recreate app="${IMAGE}:2.0"
```

Güncelleme devam ederken istek döngüsünü başlat ve kesintiyi (downtime) gör:

```bash
kubectl -n private-app exec test-client -- sh -c 'for i in $(seq 1 15); do curl -s --connect-timeout 1 http://strategy-recreate/ | grep -o "\"version\":\"[^\"]*\"" || echo "KESİNTİ (Downtime): Servis kapandı!"; sleep 0.5; done'
```

Beklenen sonuç: Eski pod'lar silinirken istekler başarısız olur (`KESİNTİ (Downtime): Servis kapandı!`), yeni sürüm pod'ları hazır olduğunda ise istekler `"version":"2.0"` olarak geri döner.

Temizlik:

```bash
kubectl -n private-app delete deployment devops-app-recreate
kubectl -n private-app delete service strategy-recreate
```

---

## 3. RollingUpdate Stratejisi — Sıfır Kesintiyi (Zero Downtime) Canlı Gör

RollingUpdate, Kubernetes'in varsayılan stratejisidir. Yeni pod'lar hazır olmadan eski pod'lar kapatılmaz; böylece sıfır kesinti sağlanır.

Aşağıdaki manifest (`starter/rolling.yaml`), sıfır kesinti politikasıyla 3 replika tanımlar:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: devops-app-rolling
  namespace: private-app
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0              # Güncelleme sırasında asla eksik pod kalmasın
      maxSurge: 1                    # En fazla 1 adet ek pod açılabilsin
  selector:
    matchLabels:
      app: devops-app-rolling
  template:
    metadata:
      labels:
        app: devops-app-rolling
    spec:
      containers:
        - name: app
          image: __IMAGE__:1.0
          ports:
            - containerPort: 8080
              name: http
---
apiVersion: v1
kind: Service
metadata:
  name: strategy-rolling
  namespace: private-app
spec:
  selector:
    app: devops-app-rolling
  ports:
    - name: http
      port: 80
      targetPort: 8080
```

Manifesti uygula ve `1.0` sürümünü başlat:

```bash
sed "s|__IMAGE__|${IMAGE}|g" starter/rolling.yaml | kubectl apply -f -
kubectl -n private-app rollout status deployment/devops-app-rolling
```

Şimdi imajı `2.0` sürümüne güncelle:

```bash
kubectl -n private-app set image deployment/devops-app-rolling app="${IMAGE}:2.0"
```

Güncelleme sırasında hemen istek döngüsünü çalıştır:

```bash
kubectl -n private-app exec test-client -- sh -c 'for i in $(seq 1 15); do curl -s --connect-timeout 1 http://strategy-rolling/ | grep -o "\"version\":\"[^\"]*\""; sleep 0.5; done'
```

Beklenen sonuç:
- Hiçbir istek hata vermez (sıfır kesinti).
- Ekranda önce `"version":"1.0"`, geçiş anında pod bazında karışık `1.0` ve `2.0`, güncelleme tamamlandığında ise tamamen `"version":"2.0"` akar.

Yapılan güncellemeyi tek komutla geri al (Rollback):

```bash
kubectl -n private-app rollout undo deployment/devops-app-rolling
kubectl -n private-app rollout status deployment/devops-app-rolling
kubectl -n private-app exec test-client -- curl -s http://strategy-rolling/
```

Beklenen sonuç: Uygulama kesintisiz biçimde yeniden `1.0` sürümüne döner.

Temizlik:

```bash
kubectl -n private-app delete deployment devops-app-rolling
kubectl -n private-app delete service strategy-rolling
```

---

## 4. Blue-Green Dağıtımı — Anlık Geçişi (Instant Switch) Canlı Gör

Blue-Green stratejisinde iki bağımsız Deployment (`blue` = v1.0, `green` = v2.0) aynı anda kümede yaşar. Servis selector'ı hangi rengi işaret ederse tüm canlı trafik anında o sürüme yönlenir.

Aşağıdaki manifestte (`starter/blue-green.yaml`):
- Blue deployment'ı doğrudan `1.0` sürümünü çalıştırır.
- Green deployment'ı doğrudan `2.0` sürümünü çalıştırır.
- `strategy-app` servisi başlangıçta `version: blue` etiketini seçer:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: devops-app-blue
  namespace: private-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: strategy-app
      version: blue
  template:
    metadata:
      labels:
        app: strategy-app
        version: blue
    spec:
      containers:
        - name: app
          image: __IMAGE__:1.0
          ports:
            - containerPort: 8080
              name: http
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: devops-app-green
  namespace: private-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: strategy-app
      version: green
  template:
    metadata:
      labels:
        app: strategy-app
        version: green
    spec:
      containers:
        - name: app
          image: __IMAGE__:2.0
          ports:
            - containerPort: 8080
              name: http
---
apiVersion: v1
kind: Service
metadata:
  name: strategy-app
  namespace: private-app
spec:
  selector:
    app: strategy-app
    version: blue                    # Başlangıçta trafiği Blue (1.0) karşılar
  ports:
    - name: http
      port: 80
      targetPort: 8080
```

Manifesti cluster'a uygula:

```bash
sed "s|__IMAGE__|${IMAGE}|g" starter/blue-green.yaml | kubectl apply -f -
kubectl -n private-app rollout status deployment/devops-app-blue
kubectl -n private-app rollout status deployment/devops-app-green
```

Mevcut canlı trafiğin Blue (`1.0`) sürümüne gittiğini doğrula:

```bash
kubectl -n private-app exec test-client -- curl -s http://strategy-app/
```

Beklenen sonuç: `{"application":"devops-app","version":"1.0","pod":"devops-app-blue-..."}` döner.

Şimdi tek bir `patch` komutu ile Service selector'ını `green` rengine çevir:

```bash
kubectl -n private-app patch service strategy-app \
  -p '{"spec":{"selector":{"app":"strategy-app","version":"green"}}}'
```

Hemen yeni istek gönder ve geçişi canlı gör:

```bash
kubectl -n private-app exec test-client -- curl -s http://strategy-app/
```

Beklenen sonuç: Hiçbir pod yeniden başlatılmadan veya beklemeden saniyeler içinde doğrudan `{"application":"devops-app","version":"2.0","pod":"devops-app-green-..."}` yanıtı alınır!

Geri alma (Rollback): Eğer Green sürümünde bir hata fark edilirse, tek bir satırla anında Blue'ya geri dönülür:

```bash
kubectl -n private-app patch service strategy-app \
  -p '{"spec":{"selector":{"app":"strategy-app","version":"blue"}}}'

kubectl -n private-app exec test-client -- curl -s http://strategy-app/
```

Temizlik:

```bash
kubectl -n private-app delete deployment devops-app-blue devops-app-green
kubectl -n private-app delete service strategy-app
```

---

## 5. Gateway API ile Canary Dağıtımı (Ağırlıklı Yönlendirme)

Canary stratejisinde canlı trafiğin ufak bir kısmı (%10) yeni sürüme (`v2`), büyük kısmı (%90) kararlı eski sürüme (`v1`) yönlendirilir.

Aşağıdaki manifest (`starter/canary-httproute.yaml`), iki sürümün servislerini ve Gateway API ağırlıklı yönlendirme kuralını tanımlar:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: strategy-app-v1
  namespace: private-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: strategy-app
      version: v1
  template:
    metadata:
      labels:
        app: strategy-app
        version: v1
    spec:
      containers:
        - name: app
          image: __IMAGE__:1.0
          ports:
            - containerPort: 8080
              name: http
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: strategy-app-v2
  namespace: private-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: strategy-app
      version: v2
  template:
    metadata:
      labels:
        app: strategy-app
        version: v2
    spec:
      containers:
        - name: app
          image: __IMAGE__:2.0
          ports:
            - containerPort: 8080
              name: http
---
apiVersion: v1
kind: Service
metadata:
  name: strategy-app-v1
  namespace: private-app
spec:
  selector:
    app: strategy-app
    version: v1
  ports:
    - name: http
      port: 80
      targetPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: strategy-app-v2
  namespace: private-app
spec:
  selector:
    app: strategy-app
    version: v2
  ports:
    - name: http
      port: 80
      targetPort: 8080
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: devops-app-canary
  namespace: private-app
spec:
  parentRefs:
    - name: devops-app-gateway
  hostnames:
    - __APP_HOST__
  rules:
    - backendRefs:
        - name: strategy-app-v1
          port: 80
          weight: 90                  # Trafiğin %90'ı kararlı v1 sürümüne
        - name: strategy-app-v2
          port: 80
          weight: 10                  # Trafiğin %10'u yeni Canary v2 sürümüne
```

Manifesti cluster'a uygula:

```bash
sed "s|__IMAGE__|${IMAGE}|g; s|__APP_HOST__|${APP_HOST}|g" starter/canary-httproute.yaml | kubectl apply -f -
kubectl -n private-app rollout status deployment/strategy-app-v1
kubectl -n private-app rollout status deployment/strategy-app-v2
```

10 adet HTTP isteği göndererek %90 / %10 dağılımını gözlemle:

```bash
for i in {1..10}; do curl -s -k "https://${APP_HOST}/" | grep -o '"version":"[^"]*"'; done
```

Beklenen sonuç: İsteklerin neredeyse tamamı `"version":"1.0"` dönerken, araya tek tük `"version":"2.0"` yanıtı düşer.

Şimdi ağırlıkları %50 / %50 olarak güncelle:

```bash
kubectl -n private-app patch httproute devops-app-canary --type=json \
  -p '[{"op":"replace","path":"/spec/rules/0/backendRefs/0/weight","value":50},{"op":"replace","path":"/spec/rules/0/backendRefs/1/weight","value":50}]'
```

Tekrar 10 adet HTTP isteği gönder:

```bash
for i in {1..10}; do curl -s -k "https://${APP_HOST}/" | grep -o '"version":"[^"]*"'; done
```

Beklenen sonuç: Yanıtlar yarı yarıya `"version":"1.0"` ve `"version":"2.0"` olarak dengeli dağılır.

---

## 6. Temizlik

```bash
kubectl delete namespace private-app
```
