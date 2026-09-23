# * Sürümü Güvenle Yayınla: Recreate, Rolling, Blue-Green ve Canary

## Amaç

Modern yazılım dağıtım stratejileri olan Recreate, RollingUpdate, Blue-Green ve Canary (Gateway API ağırlıklı yönlendirme) mimarilerini uygulamalı olarak karşılaştırmak.

## Kullanılan Kubernetes nesneleri

- **Deployment:** Recreate ve RollingUpdate stratejileri ile pod güncellemelerini yönetir.
- **Service:** Blue-Green stratejisinde pod label selector'ını anlık değiştirerek canlı trafiği yeni sürüme aktarır.
- **Gateway & HTTPRoute:** Canary stratejisinde gelen HTTP trafiğini sürümler arasında yüzdelik oranlarla (%90-%10, %50-%50) paylaştırır.

## Çalışma dizini

```bash
cd ~/k8s-labs/lab-08-deployment-strategies
```

## * Doğrulanan senaryo

İki farklı Docker imaj sürümü (`1.0` ve `2.0`) ile:
1. Recreate stratejisinde pod'ların önce sıfırlanıp sonra açılması,
2. RollingUpdate stratejisinde kesintisiz ve sırayla güncellenip `rollout undo` ile geri alınması,
3. Blue-Green stratejisinde Service selector yaması ile anında sürüm değişimi,
4. Gateway API Canary ile trafiğin ağırlıklı (%90/%10 ve %50/%50) paylaştırılması başarıyla doğrulandı.

---

## 1. İkinci İmaj Sürümünü Derle ve Değişkenleri Tanımla

Canlı güncelleme stratejilerini deneyebilmek için iki farklı sürüme (`1.0` ve `2.0`) ihtiyacımız var:

```bash
export DOCKERHUB_USER="KENDI_DOCKERHUB_KULLANICI_ADIN"
export IMAGE_V1="docker.io/${DOCKERHUB_USER}/devops-app:1.0"
export IMAGE_V2="docker.io/${DOCKERHUB_USER}/devops-app:2.0"
export STUDENT_ID="${STUDENT_ID:-$(hostname)}"
export APP_HOST="${STUDENT_ID}-app1.devopsatolyesi.com"
```

İkinci imajı (`2.0`) derleyip Docker Hub'a gönder:

```bash
docker build --build-arg APP_VERSION=2.0 -t "$IMAGE_V2" ~/k8s-labs/app/devops-app
docker push "$IMAGE_V2"
```

---

## 2. Recreate Stratejisi (Kesintili Geçiş)

Recreate stratejisinde Kubernetes, yeni sürüm pod'larını başlatmadan önce mevcut tüm eski pod'ları sonlandırır. Bu durum kısa süreli bir servis kesintisine yol açar:

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
          image: __IMAGE_V1__
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

Manifesti kopyala, `sed` ile imaj adını yerleştir ve ilk sürümü (`1.0`) başlat:

```bash
cp starter/recreate.yaml recreate.local.yaml
sed -i "s|__IMAGE_V1__|${IMAGE_V1}|g" recreate.local.yaml
kubectl apply -f recreate.local.yaml
kubectl -n private-app rollout status deployment/devops-app-recreate
```

Şimdi imajı ikinci sürüme (`2.0`) güncelle ve pod'ların önce `Terminating` olduğunu, ardından sıfırdan açıldığını izle:

```bash
kubectl -n private-app set image deployment/devops-app-recreate app="$IMAGE_V2"
kubectl -n private-app get pods -l app=devops-app-recreate -w
```
*(İzlemeyi `Ctrl+C` ile durdurun).*

---

## 3. RollingUpdate Stratejisi ve Geri Alma (Rollback)

RollingUpdate, Kubernetes'in varsayılan stratejisidir. Yeni pod'lar hazır olmadan eski pod'lar kapatılmaz; böylece sıfır kesinti sağlanır:

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
          image: __IMAGE_V1__
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

Manifesti hazırla ve `1.0` sürümünü kur:

```bash
cp starter/rolling.yaml rolling.local.yaml
sed -i "s|__IMAGE_V1__|${IMAGE_V1}|g" rolling.local.yaml
kubectl apply -f rolling.local.yaml
kubectl -n private-app rollout status deployment/devops-app-rolling
```

İmajı `2.0` sürümüne güncelle, ardından yapılan güncellemeyi tek komutla geri al (rollback):

```bash
kubectl -n private-app set image deployment/devops-app-rolling app="$IMAGE_V2"
kubectl -n private-app rollout status deployment/devops-app-rolling

# Geri alma işlemi (Rollback):
kubectl -n private-app rollout undo deployment/devops-app-rolling
kubectl -n private-app rollout status deployment/devops-app-rolling
```

Beklenen sonuç: Pod'lar kesintisiz sırayla güncellenir ve `rollout undo` ile sorunsuz biçimde önceki `1.0` sürümüne geri dönülür.

---

## 4. Blue-Green Dağıtımı

Blue-Green stratejisinde iki bağımsız Deployment (`blue` ve `green`) aynı anda kümede yaşar. Servis selector'ı hangi rengi işaret ederse tüm canlı trafik anında o renge yönlenir:

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
          image: __IMAGE_V1__
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
          image: __IMAGE_V2__
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
    version: blue                    # Başlangıçta trafiği Blue (v1.0) karşılar
  ports:
    - name: http
      port: 80
      targetPort: 8080
```

Manifesti `sed` ile hazırla ve uygula:

```bash
cp starter/blue-green.yaml blue-green.local.yaml
sed -i "s|__IMAGE_V1__|${IMAGE_V1}|g; s|__IMAGE_V2__|${IMAGE_V2}|g" blue-green.local.yaml
kubectl apply -f blue-green.local.yaml
kubectl -n private-app get pods -l app=strategy-app --show-labels
```

Canlı trafiğin Blue (`1.0`) sürümüne gittiğini doğrula:

```bash
kubectl -n private-app run strategy-check --image=curlimages/curl:8.12.1 --restart=Never -- sleep 3600
kubectl -n private-app wait --for=condition=Ready pod/strategy-check --timeout=90s
kubectl -n private-app exec strategy-check -- curl -s http://strategy-app/healthz
```

Şimdi tek bir `patch` komutu ile Service selector'ını `green` rengine çevir ve trafiğin anında `2.0` sürümüne geçtiğini gör:

```bash
kubectl -n private-app patch service strategy-app \
  -p '{"spec":{"selector":{"app":"strategy-app","version":"green"}}}'

kubectl -n private-app exec strategy-check -- curl -s http://strategy-app/healthz
kubectl -n private-app delete pod strategy-check
```

Beklenen sonuç: İkinci curl yanıtında hiçbir pod yeniden başlamadan anında `version: 2.0` döner.

---

## 5. Gateway API ile Canary Dağıtımı (Ağırlıklı Yönlendirme)

Canary stratejisinde canlı kullanıcı trafiğinin ufak bir kısmı (%10) yeni sürüme, kalanı (%90) eski sürüme gönderilir. Testler başarılı oldukça oran %50/%50 ve nihayet %100'e çıkarılır:

```yaml
# starter/canary-httproute.yaml
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

Manifesti `sed` ile hazırla ve cluster'a uygula:

```bash
cp starter/canary-httproute.yaml canary.local.yaml
sed -i "s|__IMAGE_V1__|${IMAGE_V1}|g; s|__IMAGE_V2__|${IMAGE_V2}|g; s|__APP_HOST__|${APP_HOST}|g" canary.local.yaml
kubectl apply -f canary.local.yaml
kubectl -n private-app get httproute devops-app-canary
```

Şimdi `sed` komutuyla Canary ağırlıklarını %50 / %50 olarak güncelle ve kuralı tazele:

```bash
sed -i "s/weight: 90/weight: 50/; s/weight: 10/weight: 50/" canary.local.yaml
kubectl apply -f canary.local.yaml
```

Canary trafiğini test et:

```bash
for i in {1..10}; do curl -s -k "https://${APP_HOST}/healthz"; echo ""; done
```

Beklenen sonuç: Gönderilen 10 istek arasında hem `v1` hem de `v2` yanıtlarının dengeli biçimde döndüğü gözlemlenir.
