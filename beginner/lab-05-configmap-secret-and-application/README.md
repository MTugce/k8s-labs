# Konfigürasyon, Gizli Değerler ve Uygulama Yönetimi


## Amaç

Modern bulut yerlisi (Cloud Native / 12-Factor) mimarilerde uygulama kodu ile konfigürasyon birbirinden tamamen ayrılır. Aynı konteyner imajı; test, kabul ve üretim ortamlarında yalnızca dışarıdan verilen parametrelerle (ConfigMap & Secret) çalıştırılır.

Bu laboratuvarda:
1. Gizli olmayan ayarları **ConfigMap** ile yönetmeyi,
2. Parola ve API anahtarı gibi hassas değerleri **Secret** nesnesiyle güvenli saklamayı,
3. Kendi Node.js uygulamamızı ([`app/devops-app`](../../app/devops-app)) bu konfigürasyonlarla ayağa kaldırıp `http://localhost:30087/config` üzerinden ayarların yüklendiğini canlı doğrulamayı,
4. **Public ve Private Container Image** farkını, yetkisiz çekme hatalarını (`ImagePullBackOff`) ve `imagePullSecrets` çözüm mekanizmasını öğreneceksiniz.

---

## Kullanılan Kavramlar

| Nesne / Kavram | Açıklama |
|---|---|
| **ConfigMap** | Uygulama değişkenlerini (veritabanı hostu, log seviyesi, port vb.) key-value olarak saklar. |
| **Secret** | Hassas verileri (parola, API token, sertifika) base64 formatında tutar ve Pod belleğinde şifreli/güvenli tutar. |
| **envFrom** | Bir ConfigMap veya Secret içindeki tüm key-value çiftlerini tek satırda konteynere ortam değişkeni (`env`) olarak aktarır. |
| **imagePullSecrets** | Kubelet'in private (kilitli) bir Docker registry'den güvenli şekilde imaj çekebilmesi için gereken kimlik kartıdır. |

---

## Çalışma Dizini

```bash
cd ~/k8s-labs/beginner/lab-05-configmap-secret-and-application
```

---

## 1. İzole Namespace Oluşturma

```bash
kubectl create namespace beginner-config --dry-run=client -o yaml | kubectl apply -f -
```

---

## 2. Imperative Yöntemle ConfigMap ve Secret Üretme

Hızlıca konfigürasyon üretmek için `kubectl create` komutunun `--from-literal` parametresini kullanabilirsiniz:

```bash
# Imperative ConfigMap
kubectl create configmap quick-config \
  --from-literal=ENVIRONMENT="development" \
  --from-literal=MAX_CONNECTIONS="100" \
  -n beginner-config

# Imperative Secret
kubectl create secret generic quick-secret \
  --from-literal=DB_PASSWORD="SuperSecretPassword123" \
  -n beginner-config
```

Oluşturulan nesneleri listeleyin:

```bash
kubectl get configmap,secret -n beginner-config
```

---

## 3. Declarative Manifestlerle Çalışma

Üretim ortamlarında konfigürasyonlar Git üzerinde deklaratif dosyalarla saklanır.

`starter/configmap.yaml` manifestini inceleyin:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: devops-app-config
data:
  APP_MESSAGE: "Kubernetes ve DevOps Pratikleri Harika!"
  APP_VERSION: "1.0-production"
```

`starter/secret.yaml` manifestini inceleyin. `stringData` alanı, Kubernetes'in arka planda otomatik base64 dönüşümü yapmasını sağlar:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: devops-app-secret
type: Opaque
stringData:
  APP_API_KEY: "super-secret-production-key-999"
```

Manifestleri uygulayın:

```bash
kubectl apply -f starter/configmap.yaml -n beginner-config
kubectl apply -f starter/secret.yaml -n beginner-config
```

---

## 4. Secret Değerlerini İnceleme ve Güvenlik

Secret nesnesini `describe` ettiğinizde değerlerin gizlendiğini (yalnızca byte boyutunun yazıldığını) görebilirsiniz:

```bash
kubectl describe secret devops-app-secret -n beginner-config
```

**Beklenen sonuç:** `APP_API_KEY: 31 bytes`

Secret'ın YAML çıktısını aldığınızda değer base64 formatında görünür:

```bash
kubectl get secret devops-app-secret -n beginner-config -o yaml
```

Base64 kodlanmış değeri geri çözerek doğrulayın:

```bash
kubectl get secret devops-app-secret -n beginner-config -o jsonpath='{.data.APP_API_KEY}' | base64 --decode; echo
```

**Beklenen sonuç:** `super-secret-production-key-999`

---

## 5. Uygulamamızı (`devops-app`) Dağıtma

`starter/deployment.yaml` manifestinde `envFrom` bloğu sayesinde ConfigMap ve Secret doğrudan konteynerin ortam değişkenlerine bağlanır:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: devops-app
  labels:
    app: devops-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: devops-app
  template:
    metadata:
      labels:
        app: devops-app
    spec:
      containers:
        - name: app
          image: devops-app:1.0
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 8080
          envFrom:
            - configMapRef:
                name: devops-app-config
            - secretRef:
                name: devops-app-secret
```

`starter/service.yaml` ise uygulamayı Kind cluster port haritasında ayrılan `30087` NodePort portundan dışarı açar:

```bash
kubectl apply -f starter/deployment.yaml -n beginner-config
kubectl apply -f starter/service.yaml -n beginner-config
kubectl rollout status deployment/devops-app -n beginner-config --timeout=90s
```

Pod'ların çalıştığını kontrol edin:

```bash
kubectl get pods -n beginner-config -l app=devops-app
```

---

## 6. Canlı Doğrulama: Ayarların Uygulamaya Ulaştığını Test Etme

Uygulamamızın `/config` uç noktası, ConfigMap'ten okuduğu `APP_MESSAGE` değerini ve Secret'tan `APP_API_KEY` okunup okunmadığını (`secretLoaded`) JSON olarak döndürür:

```bash
curl -s http://127.0.0.1:30087/config
```

**Beklenen sonuç:**
```json
{"message":"Kubernetes ve DevOps Pratikleri Harika!","secretLoaded":true}
```

Sağlık durumunu kontrol edin:

```bash
curl -s http://127.0.0.1:30087/healthz
```

**Beklenen sonuç:**
```json
{"status":"UP","version":"1.0-production","pod":"devops-app-..."}
```

Doğrudan konteyner içinde ortam değişkenlerini listeleyin:

```bash
APP_POD=$(kubectl get pods -n beginner-config -l app=devops-app -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n beginner-config "$APP_POD" -- printenv APP_MESSAGE APP_VERSION APP_API_KEY
```

---

## 7. Public vs Private Container Image Mantığı

Kubernetes varsayılan olarak public Docker Hub kayıt defterlerindeki imajları doğrudan çeker (`nginx`, `redis` vb.).

Ancak şirket projelerinde imajlar **Private (Özel)** depolarda tutulur ve yetkisiz erişime kapalıdır.

### Yetkisiz İmaj Hatasını Görme (`ErrImagePull`)

Kimlik bilgisi verilmemiş bir private imaj çalıştırmayı deneyelim:

```bash
kubectl apply -f starter/private-test-fail.yaml -n beginner-config
kubectl get pods -n beginner-config -l app=private-test
```

Birkaç saniye sonra Pod durumu `ErrImagePull` veya `ImagePullBackOff` olur. Hatanın nedenini `describe` ile görün:

```bash
kubectl describe pod private-image-fail -n beginner-config | grep -A 4 Events
```

**Beklenen sonuç:** `Failed to pull image ...: unauthorized` veya `pull access denied`.

### Çözüm: `imagePullSecrets` Mantığı

Kubelet'in private depodan imaj çekebilmesi için iki adım gerekir:
1. Docker giriş bilgilerini taşıyan bir secret oluşturulur:
   ```bash
   kubectl create secret docker-registry my-registry-secret \
     --docker-server=https://index.docker.io/v1/ \
     --docker-username=ornek-kullanici \
     --docker-password=ornek-parola \
     -n beginner-config
   ```
2. Pod manifestinin `spec.imagePullSecrets` alanına bu secret adı eklenir (`starter/private-test-success.yaml` dosyasını inceleyin):
   ```yaml
   spec:
     imagePullSecrets:
       - name: my-registry-secret
     containers:
       - name: app
         image: devops-app:1.0
   ```

Pod'u uygulayın:

```bash
kubectl apply -f starter/private-test-success.yaml -n beginner-config
kubectl get pod private-image-success -n beginner-config
```

Pod başarıyla `Running` durumuna geçer.

---

## 8. Temizlik (Cleanup)

```bash
kubectl delete namespace beginner-config
```
