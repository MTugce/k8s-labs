# Sürümü Güvenle Yayınla: Recreate, Rolling, Blue-Green ve Canary

| Seviye | Tahmini Süre | Profil / Araçlar | Açık Portlar |
| --- | --- | --- | --- |
| Orta | 60 dk | kubectl, Ingress, Gateway API | `19001-19003` |

## Amaç

- Aynı `devops-app` imajının `1.0` ve `2.0` sürümlerini dört dağıtım yaklaşımıyla karşılaştırmak.
- Trafik geçişini ve rollback'i gerçek HTTP yanıtlarıyla görmek.

## Adım Adım Uygulama Rehberi

Önce ikinci sürümü üretin:

```bash
export IMAGE_V1="docker.io/${DOCKERHUB_USER}/devops-app:1.0"
export IMAGE_V2="docker.io/${DOCKERHUB_USER}/devops-app:2.0"
export APP_HOST="student01-app1.devopsatolyesi.com" # kendi öğrenci kodun
docker build --build-arg APP_VERSION=2.0 -t "$IMAGE_V2" app/devops-app
docker push "$IMAGE_V2"
```

1. Recreate:

```bash
sed "s|__IMAGE_V1__|${IMAGE_V1}|g" labs/lab-09-deployment-strategies/starter/recreate.yaml | kubectl apply -f -
kubectl -n private-app set image deployment/devops-app-recreate app="$IMAGE_V2"
kubectl -n private-app rollout status deployment/devops-app-recreate
kubectl -n private-app run check-recreate --rm -it --restart=Never --image=curlimages/curl:8.12.1 -- curl -s strategy-recreate/healthz
```

2. Rolling (`maxUnavailable: 0`):

```bash
sed "s|__IMAGE_V1__|${IMAGE_V1}|g" labs/lab-09-deployment-strategies/starter/rolling.yaml | kubectl apply -f -
kubectl -n private-app set image deployment/devops-app-rolling app="$IMAGE_V2"
kubectl -n private-app rollout undo deployment/devops-app-rolling
kubectl -n private-app run check-rolling --rm -it --restart=Never --image=curlimages/curl:8.12.1 -- curl -s strategy-rolling/healthz
```

3. Blue-Green: manifesti iki sürümle uygulayın; sonra selector'ı değiştirin.

```bash
sed -e "s|__IMAGE_V1__|${IMAGE_V1}|g" -e "s|__IMAGE_V2__|${IMAGE_V2}|g" labs/lab-09-deployment-strategies/starter/blue-green.yaml | kubectl apply -f -
kubectl -n private-app patch service strategy-app -p '{"spec":{"selector":{"app":"strategy-app","version":"green"}}}'
kubectl -n private-app run check-bluegreen --rm -it --restart=Never --image=curlimages/curl:8.12.1 -- curl -s strategy-app/healthz
```

4. Canary: `backendRefs.weight` değerleriyle önce `90/10`, sonra `50/50` uygulayın.

```bash
kubectl -n private-app delete httproute devops-app-route --ignore-not-found
sed -e "s|__IMAGE_V1__|${IMAGE_V1}|g" -e "s|__IMAGE_V2__|${IMAGE_V2}|g" -e "s|__APP_HOST__|${APP_HOST}|g" labs/lab-09-deployment-strategies/starter/canary-httproute.yaml | kubectl apply -f -
kubectl -n private-app patch httproute devops-app-canary --type=json -p='[{"op":"replace","path":"/spec/rules/0/backendRefs/0/weight","value":50},{"op":"replace","path":"/spec/rules/0/backendRefs/1/weight","value":50}]'
```

Her adımda ayrı terminalde şunu çalıştırın:

```bash
while true; do curl -ks https://student01-app1.devopsatolyesi.com/healthz; sleep 1; done
```

## Doğal Doğrulama ve Beklenen Sonuç

Recreate'de kısa kesinti, Rolling'de kesintisiz değişim, Blue-Green'de selector ile anlık dönüş ve Canary'de ağırlıklı sürüm yanıtları görülmelidir.
