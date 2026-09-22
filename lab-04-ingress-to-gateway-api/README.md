# Ingress Kurallarını Gateway API'ye Taşı

Bu labı şu klasörde uygulayacaksın:

```bash
cd ~/k8s-labs/lab-04-ingress-to-gateway-api
```

## Bu labda ne yapacaksın?

NGINX Ingress ile çalışan aynı `devops-app` Service'ini Gateway API ile yayınlayacaksın. Önce `30088` portunda güvenli preview yapacak, sonra mevcut app1 DNS yolunu Gateway API'ye taşıyacaksın.

## Başlamadan önce Lab 3 kontrolü

Bu lab, Lab 3'teki `devops-app` Service ve Ingress kaynağını Gateway API'ye taşır.

```bash
kubectl -n private-app get deployment devops-app
kubectl -n private-app get service devops-app
kubectl -n private-app get ingress devops-app
```

Beklenen sonuç: Üç kaynak da bulunur; Deployment'ın `AVAILABLE` değeri sıfırdan büyük olur.

Kaynaklardan biri bulunamazsa bu labda ilerleme. Önce Lab 2 ve Lab 3'ü tamamla.

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

`starter/traefik-preview-values.yaml`, Traefik'i yalnızca ayrılmış `30088` NodePort'unda açar. NGINX Ingress çalışmaya devam eder; henüz DNS trafiği değişmez.

Önce Traefik chart repository'sini ekle.

```bash
helm repo add traefik https://traefik.github.io/charts
```

Traefik'i preview ayarlarıyla kur. `upgrade --install`, release yoksa kurar; varsa günceller.

```bash
helm upgrade --install traefik traefik/traefik --version 37.0.0 \
  --namespace traefik --create-namespace \
  --values starter/traefik-preview-values.yaml --wait
```

Kurulan Pod, Service ve GatewayClass kaynaklarını kontrol et.

```bash
kubectl -n traefik get pods,service
kubectl get gatewayclass
```

Beklenen sonuç: Traefik Pod'u `Running`, Service'i `30088` NodePort ile görünür. `traefik` GatewayClass'ı listelenir.

## 3. Gateway ve HTTPRoute oluştur

Önceki labdaki hostname'i tekrar kullan.

```bash
export STUDENT_ID="student01"
export APP_HOST="${STUDENT_ID}-app1.devopsatolyesi.com"
```

Starter manifestinin yerel kopyasını oluştur.

```bash
cp starter/gateway-route.yaml gateway-route.local.yaml
```

`gateway-route.local.yaml` dosyasını aç. `__APP_HOST__` değerini kendi DNS adınla değiştir ve kaydet.

```bash
nano gateway-route.local.yaml
```

Gateway ve HTTPRoute kaynaklarını uygula, sonra route durumunu incele.

```bash
kubectl apply -n private-app -f gateway-route.local.yaml
kubectl -n private-app wait --for=condition=Programmed gateway/devops-app-gateway --timeout=120s
kubectl -n private-app wait --for=condition=Accepted httproute/devops-app-route --timeout=120s
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

Önce yalnızca uygulamanın Ingress kaynağını sil.

```bash
kubectl delete ingress -n private-app devops-app
```

NGINX Ingress controller'a artık ihtiyaç olmadığı için namespace'ini sil.

```bash
kubectl delete namespace ingress-nginx
```

Traefik'i cutover ayarlarıyla güncelle. Bu ayar Traefik'in Kind içindeki `80` portunu dinlemesini sağlar.

```bash
helm upgrade traefik traefik/traefik --version 37.0.0 \
  --namespace traefik --values starter/traefik-cutover-values.yaml --wait
```

Pod'un çalıştığını ve DNS yolunun yanıt verdiğini doğrula.

```bash
kubectl -n traefik get pods -o wide
curl -k "https://${APP_HOST}/healthz"
```

Beklenen sonuç: Traefik control-plane içindeki `:80` portunu dinler. Mevcut `19001 → Kind :80` eşlemesi değişmez ve app1 DNS adıyla uygulama yanıt verir.
