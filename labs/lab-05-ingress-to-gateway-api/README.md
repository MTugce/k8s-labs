# Ingress Kurallarını Gateway API'ye Taşı

| Seviye | Tahmini Süre | Profil / Araçlar | Açık Portlar |
| --- | --- | --- | --- |
| Orta | 45 dk | kubectl, Helm | `19001`, `30088` |

## Amaç

- Ingress ve Gateway API'nin rol farkını görmek.
- Aynı Service'i `Gateway` ve `HTTPRoute` ile yönlendirmek.
- Edge Nginx ve DNS'e dokunmadan kontrollü geçiş yapmak.

## Adım Adım Uygulama Rehberi

Önce Gateway API CRD'lerini ve Traefik controller'ı NodePort preview modunda kurun. Preview, NGINX Ingress ile paralel doğrulama içindir.

```bash
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml
helm repo add traefik https://traefik.github.io/charts
helm upgrade --install traefik traefik/traefik --version 37.0.0 \
  -n traefik --create-namespace \
  -f platform/traefik-preview-values.yaml --wait
```

```bash
export APP_HOST="student01-app1.devopsatolyesi.com"
sed "s/__APP_HOST__/${APP_HOST}/g" labs/lab-05-ingress-to-gateway-api/starter/gateway-route.yaml | kubectl apply -n private-app -f -
curl -H "Host: ${APP_HOST}" http://SUNUCU_IP:30088/healthz
```

Preview doğrulandıktan sonra geçiş yapın. Bu, yalnızca bu öğrencinin Kind kümesindeki NGINX Ingress'i kaldırır; hosttaki Edge Nginx ve Cloudflare değişmez.

```bash
kubectl delete ingress -n private-app devops-app
kubectl delete namespace ingress-nginx
helm upgrade traefik traefik/traefik --version 37.0.0 -n traefik \
  -f platform/traefik-cutover-values.yaml --wait
curl -k "https://${APP_HOST}/healthz"
```

Cutover values, Traefik'i control-plane üzerinde `hostNetwork: true` ile :80'e bağlar. Bu nedenle mevcut `19001 → Kind :80` eşlemesi ve aynı `app1` DNS adı korunur.

## Doğal Doğrulama ve Beklenen Sonuç

Önce `30088` preview yanıtı, cutover sonrasında `https://student01-app1.devopsatolyesi.com/healthz` yanıtı alınır. Geçiş boyunca Edge Nginx yapılandırılmaz.
