# Kendi Docker İmajını Private Docker Hub'dan Çalıştır

| Seviye | Tahmini Süre | Profil / Araçlar | Açık Portlar |
| --- | --- | --- | --- |
| Temel-Orta | 55 dk | Docker, kubectl | `30087` |

## Amaç

- `devops-app:1.0` imajını kendi private Docker Hub repository'nize göndermek.
- ConfigMap ve Secret'ı Deployment'a enjekte etmek.
- `imagePullSecret` ile private imajı kubelet'in çekmesini sağlamak.

## Adım Adım Uygulama Rehberi

```bash
export DOCKERHUB_USER="kendi_kullanici_adin"
export IMAGE_REPOSITORY="devops-app"
export IMAGE_TAG="1.0"
export IMAGE="docker.io/${DOCKERHUB_USER}/${IMAGE_REPOSITORY}:${IMAGE_TAG}"

docker build -t "$IMAGE" app/devops-app
docker login
docker push "$IMAGE"
kubectl create namespace private-app
```

Önce `imagePullSecret` olmadan deneyin. Private repository nedeniyle Pod'un `ImagePullBackOff` olduğunu inceleyin:

```bash
kubectl apply -f labs/lab-03-private-dockerhub-image-configmap-secret/starter/configmap.yaml -n private-app
sed "s|__IMAGE__|${IMAGE}|g" labs/lab-03-private-dockerhub-image-configmap-secret/starter/deployment.yaml | kubectl apply -n private-app -f -
kubectl -n private-app describe pod -l app=devops-app
```

Docker Hub access token ile registry Secret oluşturun:

```bash
read -rsp "Docker Hub access token: " DOCKERHUB_TOKEN; echo
read -rp "Docker Hub e-posta adresi: " DOCKERHUB_EMAIL
kubectl -n private-app create secret docker-registry dockerhub-creds \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username="$DOCKERHUB_USER" \
  --docker-password="$DOCKERHUB_TOKEN" \
  --docker-email="$DOCKERHUB_EMAIL"
```

`create secret docker-registry`, Docker yapılandırmasını Kubernetes'in `.data` alanına Base64 kodlayarak yazar. Genel uygulama Secret'ında ise `stringData` kullanılır; API sunucusu bunu `.data` içinde Base64'e çevirir. Base64 şifreleme değildir:

```bash
read -rsp "Uygulama API anahtarı: " APP_API_KEY; echo
printf '%s' "$APP_API_KEY" | base64
```

`secrets.local.yaml` dosyasını şablondan oluşturun, `stringData` alanına yalnızca kendi yerel değerinizi yazın. Bu dosya Git'e girmez.

```bash
cp labs/lab-03-private-dockerhub-image-configmap-secret/starter/secret.example.yaml secrets.local.yaml
${EDITOR:-vi} secrets.local.yaml
kubectl apply -f secrets.local.yaml -n private-app
sed "s|__IMAGE__|${IMAGE}|g" labs/lab-03-private-dockerhub-image-configmap-secret/starter/deployment-with-pull-secret.yaml | kubectl apply -n private-app -f -
kubectl apply -f labs/lab-03-private-dockerhub-image-configmap-secret/starter/service.yaml -n private-app
kubectl -n private-app rollout status deployment/devops-app
curl http://SUNUCU_IP:30087/config
```

## Doğal Doğrulama ve Beklenen Sonuç

```bash
kubectl -n private-app get pod,secret
curl http://SUNUCU_IP:30087/healthz
```

Pod `Running` olmalı; `/config` yanıtı `secretLoaded: true` göstermeli, Secret değeri ise hiç gösterilmemelidir.
