# Ingress Kurallarını Gateway API'ye Taşı

| Seviye | Tahmini Süre | Profil / Araçlar | Açık Portlar |
| --- | --- | --- | --- |
| Orta | 50 dk | kubectl, Helm | `19001`, `30088` |

## Bu labda ne yapacaksın?

NGINX Ingress ile çalışan aynı `devops-app` Service'ini Gateway API ile yayınlayacaksın. Önce `30088` portunda güvenli preview yapacak, sonra mevcut app1 DNS yolunu Gateway API'ye taşıyacaksın.

## Ingress ve Gateway API farkı

- Ingress, host/path ve backend bilgisini tek nesnede tutar.
- Gateway API'de controller'ı `GatewayClass`, giriş noktasını `Gateway`, yönlendirmeyi `HTTPRoute` tanımlar.
- Uygulama sahibi HTTPRoute yazar; platform sahibi Gateway'i yönetebilir.

## 1. Gateway API kaynak türlerini ekle

Kubernetes, Gateway ve HTTPRoute türlerini varsayılan olarak bilmez. Önce CRD'leri ekle.

```bash
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml
kubectl get crd | grep gateway.networking.k8s.io
```

Beklenen sonuç: `gateways.gateway.networking.k8s.io` ve `httproutes.gateway.networking.k8s.io` görünür.

## 2. Traefik'i preview modunda kur

`platform/traefik-preview-values.yaml`, Traefik'i yalnızca ayrılmış `30088` NodePort'unda açar. NGINX Ingress çalışmaya devam eder; henüz DNS trafiği değişmez.

```bash
helm repo add traefik https://traefik.github.io/charts
helm upgrade --install traefik traefik/traefik --version 37.0.0 \
  --namespace traefik --create-namespace \
  --values platform/traefik-preview-values.yaml --wait
kubectl -n traefik get pods,service
kubectl get gatewayclass
```

Beklenen sonuç: Traefik Pod'u `Running`, Service'i `30088` NodePort ile görünür. `traefik` GatewayClass'ı listelenir.

## 3. Gateway ve HTTPRoute oluştur

Önceki labdaki hostname'i tekrar kullan.

```bash
export STUDENT_ID="student01"
export APP_HOST="${STUDENT_ID}-app1.devopsatolyesi.com"
sed "s/__APP_HOST__/${APP_HOST}/g" labs/lab-05-ingress-to-gateway-api/starter/gateway-route.yaml | kubectl apply -n private-app -f -
kubectl -n private-app get gateway,httproute
kubectl -n private-app describe httproute devops-app-route
```

Beklenen sonuç: HTTPRoute `Accepted` ve `ResolvedRefs` koşulları `True` olur. Bu, Service adının bulunduğunu ve controller'ın route'u kabul ettiğini gösterir.

## 4. DNS'i değiştirmeden preview testi yap

Trafiği önce doğrudan Traefik preview portuna gönder. Host header, HTTPRoute'un hostname kuralını eşleştirir.

```bash
curl -H "Host: ${APP_HOST}" http://SUNUCU_IP:30088/healthz
```

Beklenen sonuç: `status: UP`. NGINX Ingress üzerinden çalışan `https://${APP_HOST}` adresi bu aşamada hâlâ çalışır.

## 5. Gateway API'ye cutover yap

Preview başarılıysa yalnızca Kind içindeki NGINX Ingress controller'ı kaldır. Hosttaki Edge Nginx ve Cloudflare ayarlarını değiştirme.

```bash
kubectl delete ingress -n private-app devops-app
kubectl delete namespace ingress-nginx
helm upgrade traefik traefik/traefik --version 37.0.0 \
  --namespace traefik --values platform/traefik-cutover-values.yaml --wait
kubectl -n traefik get pods -o wide
curl -k "https://${APP_HOST}/healthz"
```

Beklenen sonuç: Traefik control-plane içindeki `:80` portunu dinler. Mevcut `19001 → Kind :80` eşlemesi değişmez ve app1 DNS adıyla uygulama yanıt verir.
