# ConfigMap, Secret ve Private Container Image

> **Seviye:** Başlangıç / Orta
> **Tahmini süre:** Çekirdek 45 dakika, ek görev 30 dakika
> **Ön koşul:** Beginner Lab 2 ve Docker temel bilgisi
> **Eğitim durumu:** ConfigMap/Secret zorunlu; private registry ek görev

## Amaç

Önce uygulama ayarlarını ConfigMap ve Secret ile Pod'a aktaracaksınız. Ardından isteğe bağlı bölümde private Docker Hub image'ının kimlik bilgisi olmadan çekilemediğini görecek ve `imagePullSecret` ile hatayı çözeceksiniz.

## Kullanılan Kubernetes nesneleri

- **ConfigMap:** Gizli olmayan uygulama ayarlarını taşır.
- **Secret:** Parola, token ve API anahtarı gibi hassas değerleri taşır.
- **Deployment:** Uygulama Pod'larını yönetir.
- **Service:** Uygulamayı sabit bir adres ve NodePort ile açar.
- **imagePullSecret:** Private registry kimlik bilgisini kubelet'e verir.

## Çalışma dizini

```bash
cd ~/k8s-labs/beginner/lab-03-configmap-secret-private-image
```

# Bölüm A — Zorunlu: ConfigMap ve Secret

## 1. Uygulama image'ını yerel olarak hazırla

```bash
docker build -t devops-app:1.0 ~/k8s-labs/app/devops-app
kind load docker-image devops-app:1.0 --name k8s-labs
```

Image'ın node'lara yüklendiğini kontrol edin:

```bash
docker exec k8s-labs-control-plane crictl images | grep devops-app
```

## 2. Namespace ve ConfigMap oluştur

```bash
kubectl create namespace private-app --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f starter/configmap.yaml
kubectl get configmap devops-app-config -n private-app -o yaml
```

ConfigMap içinde iki gizli olmayan değer bulunur:

- `APP_MESSAGE`: Uygulamanın `/config` çıktısında görünen mesaj
- `APP_VERSION`: Uygulama sürümü

## 3. Uygulama Secret'ını oluştur

Örnek manifest `stringData` kullanır. Kubernetes bu değeri kaydederken base64 biçimine çevirir.

```bash
export APP_API_KEY="gizli-anahtar-degeri-123"
sed "s|__APP_API_KEY__|${APP_API_KEY}|g" starter/secret.example.yaml | kubectl apply -f -
kubectl get secret devops-app-secret -n private-app
```

Secret anahtarlarını görüntüleyin; değer doğrudan yazdırılmaz:

```bash
kubectl describe secret devops-app-secret -n private-app
```

Eğitim amacıyla değeri geri çözün:

```bash
kubectl get secret devops-app-secret -n private-app \
  -o jsonpath='{.data.APP_API_KEY}' | base64 --decode; echo
```

> Gerçek sistemlerde Secret değerlerini terminale yazdırmayın ve Git'e eklemeyin.

## 4. Deployment ve Service'i başlat

Yerel image kullanan Deployment, ConfigMap ve Secret içindeki bütün değerleri `envFrom` ile container'a aktarır:

```bash
kubectl apply -f starter/deployment-local.yaml
kubectl apply -f starter/service.yaml
kubectl rollout status deployment/devops-app -n private-app --timeout=120s
kubectl get pods,service -n private-app
```

Beklenen sonuç: İki Pod `Running` olur ve `devops-app` Service'i `30087` NodePort portunu kullanır.

## 5. ConfigMap ve Secret değerlerini doğrula

NodePort üzerinden uygulamayı test edin:

```bash
curl -s http://127.0.0.1:30087/config; echo
curl -s http://127.0.0.1:30087/healthz; echo
```

Beklenen sonuç:

- `/config`: ConfigMap mesajını ve `"secretLoaded":true` değerini döndürür.
- `/healthz`: `"status":"UP"` döndürür.

Değerleri doğrudan çalışan container içinde de kontrol edin:

```bash
export APP_POD="$(kubectl get pod -n private-app -l app=devops-app -o jsonpath='{.items[0].metadata.name}')"
kubectl exec -n private-app "$APP_POD" -- printenv APP_MESSAGE APP_VERSION APP_API_KEY
```

# Bölüm B — Orta Seviye Ek Görev: Private Docker Hub

Bu bölüm için private Docker Hub repository ve Personal Access Token gerekir. Temel eğitim akışı bu bölüme bağlı değildir.

## 6. Private repository ve image hazırla

Docker Hub'da `devops-app` adında **Private** repository oluşturun. Ardından:

```bash
export DOCKERHUB_USER="KENDI_DOCKERHUB_KULLANICI_ADIN"
export PRIVATE_IMAGE="docker.io/${DOCKERHUB_USER}/devops-app:1.0"

docker tag devops-app:1.0 "$PRIVATE_IMAGE"
docker login -u "$DOCKERHUB_USER"
docker push "$PRIVATE_IMAGE"
```

## 7. Kimlik bilgisi olmadan hatayı gözlemle

Mevcut Deployment'ı private image kullanacak biçimde güncelleyin:

```bash
sed "s|__IMAGE__|${PRIVATE_IMAGE}|g" starter/deployment.yaml | kubectl apply -f -
kubectl get pods -n private-app
```

Bir süre sonra yeni Pod `ErrImagePull` veya `ImagePullBackOff` durumuna geçer. Nedeni inceleyin:

```bash
kubectl describe pod -n private-app -l app=devops-app
```

## 8. Registry Secret oluştur ve hatayı düzelt

Parolayı komut geçmişine yazmamak için gizli giriş kullanın:

```bash
read -rsp "Docker Hub token: " DOCKERHUB_TOKEN; echo

kubectl create secret docker-registry dockerhub-creds -n private-app \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username="$DOCKERHUB_USER" \
  --docker-password="$DOCKERHUB_TOKEN"
```

`imagePullSecrets` kullanan final Deployment'ı uygulayın:

```bash
sed "s|__IMAGE__|${PRIVATE_IMAGE}|g" starter/deployment-with-pull-secret.yaml | kubectl apply -f -
kubectl rollout status deployment/devops-app -n private-app --timeout=180s
kubectl get pods -n private-app
```

Beklenen sonuç: Private image başarıyla çekilir ve iki Pod `Running` olur.

## Başarı kriterleri

- ConfigMap ile Secret arasındaki farkı açıklayabiliyorsunuz.
- Her iki kaynağın değerlerini container'a aktarabildiniz.
- Uygulamanın Secret değerini aldığını değerini göstermeden doğruladınız.
- Ek görevde `ImagePullBackOff` hatasını `imagePullSecret` ile çözdünüz.

## Temizlik

```bash
kubectl delete namespace private-app
unset APP_API_KEY DOCKERHUB_TOKEN
```
