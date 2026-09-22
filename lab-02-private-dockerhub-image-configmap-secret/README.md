# * Kendi Docker İmajını Private Docker Hub'dan Çalıştır

## Amaç

Private Docker Hub imajını ConfigMap, Secret ve `imagePullSecrets` ile Kubernetes'te çalıştırmak.

## Kullanılan Kubernetes nesneleri

- **Deployment:** Private imajdan uygulama Pod'larını çalıştırır.
- **ConfigMap:** Gizli olmayan uygulama ayarlarını taşır.
- **Secret:** Gizli değerleri ve registry giriş bilgisini taşır.
- **Service:** Uygulama Pod'larına cluster içinden erişim sağlar.

## Çalışma dizini

```bash
cd ~/k8s-labs/lab-02-private-dockerhub-image-configmap-secret
```

## Erişim

- URL: `http://SUNUCU_IP:30087/healthz` ve `http://SUNUCU_IP:30087/config`
- Kimlik doğrulaması: yok

## * Doğrulanan senaryo

Private Docker Hub imajı `imagePullSecrets` ile çekildi. `/healthz` isteği
`status: UP`, `/config` isteği ise ConfigMap mesajı ve `secretLoaded: true`
değeri döndürdü.

## 1. Private Docker Hub repository oluştur

Tarayıcıda Docker Hub hesabını aç. **Create repository** seç, adını `devops-app` yaz ve görünürlüğü **Private** yap.

Terminalde image adını oluştur.

```bash
export DOCKERHUB_USER="KENDI_DOCKERHUB_KULLANICI_ADIN"
export IMAGE_REPOSITORY="devops-app"
export IMAGE_TAG="1.0"
export IMAGE="docker.io/${DOCKERHUB_USER}/${IMAGE_REPOSITORY}:${IMAGE_TAG}"
echo "$IMAGE"
```

Beklenen sonuç: `docker.io/kullanici/devops-app:1.0` biçiminde image adı görünür. Yeni bir uygulama için yeni repository açılır; farklı uygulamalar aynı repository içinde karıştırılmaz.

## 2. Uygulamayı Docker image yap

Uygulama kaynakları lab klasöründe değil, repo kökündeki `~/k8s-labs/app/devops-app` dizinindedir. `Dockerfile`, Node.js uygulamasını `8080` portunda çalıştırır. Önce image'i yerelde üret.

```bash
docker build -t "$IMAGE" ~/k8s-labs/app/devops-app
docker images "$IMAGE"
```

Beklenen sonuç: image listede `1.0` tag'iyle görünür.

Docker Hub'a giriş yap ve image'i private repository'ye gönder.

```bash
docker login
docker push "$IMAGE"
```

Beklenen sonuç: push sonunda `1.0` tag'i görünür. Docker Hub sayfasını yenilediğinde image repository içinde listelenir.

## 3. Private image'i Secret olmadan dene

Bu adım bilerek başarısız olur. Kubernetes, private repository'den image çekmek için Docker Hub giriş bilgisine ihtiyaç duyar.

Önce bu uygulama için namespace oluştur.

```bash
kubectl create namespace private-app
```

Uygulamanın hassas olmayan ayarlarını ConfigMap olarak ekle.

```bash
kubectl apply -n private-app -f starter/configmap.yaml
```

Başlangıç manifestinin yerel bir kopyasını oluştur.

```bash
cp starter/deployment.yaml deployment.local.yaml
```

`deployment.local.yaml` dosyasını aç. `image: __IMAGE__` satırını terminalde gördüğün `$IMAGE` değeriyle değiştir ve kaydet.

```bash
nano deployment.local.yaml
```

Yerel manifestini uygula ve Pod durumunu gör.

```bash
kubectl apply -n private-app -f deployment.local.yaml
kubectl -n private-app get pods
```

Image çekme hatasının nedenini Events bölümünde incele.

```bash
kubectl -n private-app describe pod -l app=devops-app
```

Beklenen sonuç: Pod `ErrImagePull` veya `ImagePullBackOff` olur. `describe` çıktısındaki Events bölümü image çekme yetkisinin olmadığını gösterir.

## 4. Docker Hub girişini registry Secret olarak oluştur

Docker Hub → Account Settings → Personal access tokens alanından bir token oluştur. Token'ı ekrana, Git'e veya manifest dosyasına yazma.

```bash
read -rp "Docker Hub e-posta adresi: " DOCKERHUB_EMAIL
read -rsp "Docker Hub access token: " DOCKERHUB_TOKEN; echo
kubectl -n private-app create secret docker-registry dockerhub-creds \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username="$DOCKERHUB_USER" \
  --docker-password="$DOCKERHUB_TOKEN" \
  --docker-email="$DOCKERHUB_EMAIL"
kubectl -n private-app get secret dockerhub-creds
```

Beklenen sonuç: `dockerhub-creds` görünür. Kubernetes bu Secret'ı Pod başlamadan önce image çekmek için kullanacaktır.

## 5. Uygulama Secret'ını `stringData` ile hazırla

`stringData`, Secret değerini yerel YAML dosyasında okunabilir olarak yazmanı sağlar. Kubernetes kaydederken değeri `.data` alanında Base64'e çevirir. Base64 şifreleme değildir.

```bash
cp ~/k8s-labs/lab-02-private-dockerhub-image-configmap-secret/starter/secret.example.yaml secrets.local.yaml
nano secrets.local.yaml
```

Yalnızca `APP_API_KEY` alanındaki şablon metnini kendi geçici değerinle değiştir ve kaydet. `secrets.local.yaml` Git'e eklenmez.

İstersen Base64 dönüşümünü kendi terminalinde gör:

```bash
read -rsp "Uygulama API anahtarı: " APP_API_KEY; echo
printf '%s' "$APP_API_KEY" | base64
```

Bu çıktı bir örnek parola değildir; `stringData` arkasındaki dönüşümü göstermek içindir.

## 6. Uygulamayı ConfigMap, Secret ve imagePullSecret ile çalıştır

Final Deployment, ayarları ConfigMap'ten, hassas değeri Secret'tan ve registry girişini `dockerhub-creds` Secret'ından alır.

Önce yerel Secret dosyanı cluster'a gönder.

```bash
kubectl apply -n private-app -f secrets.local.yaml
```

Image çekme Secret'ını kullanan manifestin yerel kopyasını oluştur.

```bash
cp starter/deployment-with-pull-secret.yaml deployment-final.local.yaml
```

`deployment-final.local.yaml` dosyasında `image: __IMAGE__` satırını `$IMAGE` değeriyle değiştir ve kaydet.

```bash
nano deployment-final.local.yaml
```

Final Deployment'ı ve Service'i uygula.

```bash
kubectl apply -n private-app -f deployment-final.local.yaml
kubectl apply -n private-app -f starter/service.yaml
```

Deployment'ın hazır olmasını bekle, sonra kaynakları listele.

```bash
kubectl -n private-app rollout status deployment/devops-app
kubectl -n private-app get pods,service
```

Beklenen sonuç: iki Pod `Running` olur ve Service'te `30087` NodePort görünür.

## 7. Uygulamayı doğrula

```bash
curl http://SUNUCU_IP:30087/config
curl http://SUNUCU_IP:30087/healthz
```

İlk yanıtta ConfigMap mesajı ve `secretLoaded: true` görünür. Secret'ın gerçek değeri hiçbir yanıtta görünmez. İkinci yanıtta `status: UP` görünür.
