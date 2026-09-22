# Sürümü Güvenle Yayınla: Recreate, Rolling, Blue-Green ve Canary

Bu labı şu klasörde uygulayacaksın:

```bash
cd ~/k8s-labs/lab-08-deployment-strategies
```

## Bu labda ne yapacaksın?

`devops-app:1.0` ve `devops-app:2.0` sürümlerini kullanarak dört yayın yaklaşımını karşılaştıracaksın. Her yaklaşımda hangi Pod'un trafik aldığını ve gerektiğinde rollback işlemini göreceksin.

## 1. İkinci image sürümünü üret

İlk private image labında `1.0` image'ini gönderdin. Aynı uygulamayı `APP_VERSION=2.0` build argümanıyla yeniden üret.

```bash
export IMAGE_V1="docker.io/${DOCKERHUB_USER}/devops-app:1.0"
export IMAGE_V2="docker.io/${DOCKERHUB_USER}/devops-app:2.0"
export APP_HOST="student01-app1.devopsatolyesi.com"
docker build --build-arg APP_VERSION=2.0 -t "$IMAGE_V2" app/devops-app
docker push "$IMAGE_V2"
```

Beklenen sonuç: Docker Hub'daki aynı `devops-app` repository'sinde iki ayrı tag bulunur: `1.0` ve `2.0`.

## 2. Recreate stratejisini uygula

Recreate, eski Pod'ları tamamen kapatır; yenileri ondan sonra açılır. Kısa kesinti riski vardır.

```bash
sed "s|__IMAGE_V1__|${IMAGE_V1}|g" ~/k8s-labs/lab-08-deployment-strategies/starter/recreate.yaml | kubectl apply -f -
kubectl -n private-app rollout status deployment/devops-app-recreate
kubectl -n private-app set image deployment/devops-app-recreate app="$IMAGE_V2"
kubectl -n private-app get pods -l app=devops-app-recreate -w
```

Beklenen sonuç: eski Pod'lar sonlanır, sonra yeni Pod'lar oluşur. İzlemeyi `Ctrl+C` ile bitir.

## 3. RollingUpdate ve rollback uygula

RollingUpdate, yeni Pod'ları eski Pod'lar tamamen kapanmadan başlatır. Bu manifestte `maxUnavailable: 0` olduğu için hazır Pod sayısı düşmez.

```bash
sed "s|__IMAGE_V1__|${IMAGE_V1}|g" ~/k8s-labs/lab-08-deployment-strategies/starter/rolling.yaml | kubectl apply -f -
kubectl -n private-app rollout status deployment/devops-app-rolling
kubectl -n private-app set image deployment/devops-app-rolling app="$IMAGE_V2"
kubectl -n private-app rollout status deployment/devops-app-rolling
kubectl -n private-app rollout undo deployment/devops-app-rolling
```

Beklenen sonuç: image değişiminde Pod'lar sırayla yenilenir. Son komut Deployment'ı önceki `1.0` revision'ına döndürür.

## 4. Blue-Green geçişi yap

Blue ve green iki ayrı Deployment'tır. Service selector'ı hangi rengi seçerse trafik o renge gider.

```bash
sed -e "s|__IMAGE_V1__|${IMAGE_V1}|g" -e "s|__IMAGE_V2__|${IMAGE_V2}|g" \
  ~/k8s-labs/lab-08-deployment-strategies/starter/blue-green.yaml | kubectl apply -f -
kubectl -n private-app get pods -l app=strategy-app --show-labels
kubectl -n private-app run check-blue --rm -it --restart=Never \
  --image=curlimages/curl:8.12.1 -- curl -s strategy-app/healthz
```

Beklenen sonuç: ilk istek `version: 1.0` döndürür; Service başlangıçta blue Pod'larını seçer.

Service selector'ını green'e çevir.

```bash
kubectl -n private-app patch service strategy-app \
  -p '{"spec":{"selector":{"app":"strategy-app","version":"green"}}}'
kubectl -n private-app run check-green --rm -it --restart=Never \
  --image=curlimages/curl:8.12.1 -- curl -s strategy-app/healthz
```

Beklenen sonuç: ikinci istek `version: 2.0` döndürür. Pod yeniden yaratmadan trafik yönü değişmiştir.

## 5. Gateway API ile Canary dağıtımı yap

Canary'de iki Service aynı HTTPRoute içinde ağırlık alır. Önce Gateway API labındaki `devops-app-gateway` kaynaklarının çalıştığını doğrula.

```bash
kubectl -n private-app get gateway devops-app-gateway
kubectl -n private-app delete httproute devops-app-route --ignore-not-found
sed -e "s|__IMAGE_V1__|${IMAGE_V1}|g" -e "s|__IMAGE_V2__|${IMAGE_V2}|g" \
  -e "s|__APP_HOST__|${APP_HOST}|g" \
  ~/k8s-labs/lab-08-deployment-strategies/starter/canary-httproute.yaml | kubectl apply -f -
kubectl -n private-app get httproute devops-app-canary -o yaml
```

Beklenen sonuç: HTTPRoute'ta v1 için `90`, v2 için `10` ağırlığı görünür.

Trafiği yarı yarıya böl ve route'u tekrar incele.

```bash
kubectl -n private-app patch httproute devops-app-canary --type=json \
  -p='[{"op":"replace","path":"/spec/rules/0/backendRefs/0/weight","value":50},{"op":"replace","path":"/spec/rules/0/backendRefs/1/weight","value":50}]'
curl -k "https://${APP_HOST}/healthz"
```

Beklenen sonuç: HTTPRoute ağırlıkları `50/50` olur. Tek bir istekte hangi sürümün döneceği değişebilir; çok sayıda istek atıldığında iki sürümün de yanıt verdiği görülür.
