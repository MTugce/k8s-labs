# * Kendi Docker İmajını Private Docker Hub'dan Çalıştır

## Amaç

Private Docker Hub imajını ConfigMap, Secret ve `imagePullSecrets` ile Kubernetes'te çalıştırmak.

## Kullanılan Kubernetes nesneleri

- **Deployment:** Private imajdan uygulama Pod'larını çalıştırır.
- **ConfigMap:** Gizli olmayan uygulama ayarlarını taşır.
- **Secret:** Gizli değerleri ve registry giriş bilgisini taşır.
- **Service:** Uygulama Pod'larına cluster içinden ve NodePort üzerinden erişim sağlar.

## Çalışma dizini

```bash
cd ~/k8s-labs/lab-02-private-dockerhub-image-configmap-secret
```

---

## 1. Private Docker Hub repository oluştur

Tarayıcıda Docker Hub hesabını aç. **Create repository** seç, adını `devops-app` yaz ve görünürlüğü **Private** yap.

Terminalde imaj adını tanımla:

```bash
export DOCKERHUB_USER="KENDI_DOCKERHUB_KULLANICI_ADIN"
export IMAGE="docker.io/${DOCKERHUB_USER}/devops-app:1.0"
echo "İmaj adı: $IMAGE"
```

---

## 2. Uygulamayı derle ve Docker Hub'a gönder

Uygulama kaynakları `~/k8s-labs/app/devops-app` dizinindedir.

İmajı derle:

```bash
docker build -t "$IMAGE" ~/k8s-labs/app/devops-app
docker images "$IMAGE"
```

Docker Hub'a giriş yap ve imajı private depoya gönder:

```bash
docker login -u "$DOCKERHUB_USER"
docker push "$IMAGE"
```

---

## 3. Private imajı Secret olmadan dene (Hata Senaryosu)

Bu adımda Kubernetes'in kimlik bilgisi olmadan private depodan imaj çekemediğini gözlemleyeceksin.

Namespace ve ConfigMap oluştur:

```bash
kubectl create namespace private-app --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f starter/configmap.yaml
```

Manifesti kopyala ve `sed` ile imaj adını otomatik yerleştir:

```bash
cp starter/deployment.yaml deployment.local.yaml
sed -i "s|__IMAGE__|${IMAGE}|g" deployment.local.yaml
kubectl apply -f deployment.local.yaml
```

Pod durumunu ve hatayı incele:

```bash
kubectl -n private-app get pods
kubectl -n private-app describe pod -l app=devops-app | grep -E "ImagePullBackOff|ErrImagePull"
```

Beklenen sonuç: Pod `ImagePullBackOff` veya `ErrImagePull` hatası verir.

---

## 4. Docker Hub erişim Secret'ını oluştur (`docker-registry`)

Docker Hub Personal Access Token veya parolanız ile Kubernetes'e image çekme yetkisi tanımlayın:

```bash
read -rp "Docker Hub kullanıcı adı: " DOCKERHUB_USER
read -rsp "Docker Hub token veya parola: " DOCKERHUB_PASS; echo

kubectl -n private-app create secret docker-registry dockerhub-creds \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username="$DOCKERHUB_USER" \
  --docker-password="$DOCKERHUB_PASS"

kubectl -n private-app get secret dockerhub-creds
```

---

## 5. Uygulama Secret'ını hazırla (`stringData`)

Uygulamanın ihtiyaç duyduğu API anahtarını tanımlayan Secret manifestini kopyala ve `sed` ile oluştur:

```bash
export APP_API_KEY="gizli-anahtar-degeri-123"

cp starter/secret.example.yaml secrets.local.yaml
sed -i "s|__APP_API_KEY__|${APP_API_KEY}|g" secrets.local.yaml
kubectl apply -f secrets.local.yaml
kubectl -n private-app get secret devops-app-secret
```

---

## 6. Final Deployment ve Service'i çalıştır

Hem `dockerhub-creds` çekme yetkisini hem de ConfigMap ve Secret değerlerini kullanan final manifesti hazırla ve uygula:

```bash
cp starter/deployment-with-pull-secret.yaml deployment-final.local.yaml
sed -i "s|__IMAGE__|${IMAGE}|g" deployment-final.local.yaml
kubectl apply -f deployment-final.local.yaml
kubectl apply -f starter/service.yaml
```

Deployment'ın hazır olmasını bekle:

```bash
kubectl -n private-app rollout status deployment/devops-app
kubectl -n private-app get pods,service
```

Beklenen sonuç: Pod'lar `Running` olur ve Service `30087` NodePort portu ile listelenir.

---

## 7. Uygulamayı doğrula

```bash
curl -s http://127.0.0.1:30087/config
echo ""
curl -s http://127.0.0.1:30087/healthz
echo ""
```

Beklenen sonuç:
- `/config` isteği: ConfigMap mesajını ve `"secretLoaded": true` değerini döner.
- `/healthz` isteği: `"status": "UP"` döner.
