# * Ingress Kurallarını Gateway API'ye Taşı

## Amaç

Mevcut Ingress yönlendirmesini, DNS ve host Nginx ayarlarını değiştirmeden Kubernetes Gateway API standartlarına taşımak.

## Kullanılan Kubernetes nesneleri

- **GatewayClass:** Gateway controller türünü tanımlar (`traefik`).
- **Gateway:** Cluster'daki trafik giriş noktasını tanımlar.
- **HTTPRoute:** Host/path trafiğini hedef Service'e yönlendiren Gateway API kuralıdır.
- **Service:** HTTPRoute'un uygulama backend'idir.

## Çalışma dizini

```bash
cd ~/k8s-labs/lab-04-ingress-to-gateway-api
```

## Gateway API mimarisi

```text
İstemci → DNS / Edge Nginx → 19001 → Kind control-plane :80
        → Traefik Gateway controller → Gateway → HTTPRoute → Service → Pod
```

- **Ingress:** Host/path ve backend bilgisini tek bir nesnede toplar.
- **Gateway API:** Giriş noktasını (`Gateway`) platform ekibinin, yönlendirmeyi (`HTTPRoute`) ise uygulama ekibinin yönetmesini sağlayarak yetkileri ayrıştırır.

---

## 1. Gateway API kaynak türlerini (CRD) ekle

Kubernetes, Gateway ve HTTPRoute türlerini varsayılan olarak tanımaz; önce standart CRD'leri ekle:

```bash
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml
kubectl get crd | grep gateway.networking.k8s.io
```

Beklenen sonuç: `gateways.gateway.networking.k8s.io` ve `httproutes.gateway.networking.k8s.io` kaynakları listelenir.

---

## 2. Traefik'i preview modunda kur

`starter/traefik-preview-values.yaml`, Traefik'i mevcut NGINX Ingress trafiğini bozmadan, ayrılmış `30088` NodePort portunda açar:

```yaml
ingressClass:
  enabled: false
providers:
  kubernetesIngress:
    enabled: false
  kubernetesGateway:
    enabled: true
gateway:
  enabled: false
gatewayClass:
  enabled: true
ports:
  web:
    port: 80
    exposedPort: 80
    nodePort: 30088
    expose:
      default: true
service:
  type: NodePort
```

Traefik helm reposunu ekle ve preview yapılandırmasıyla kur:

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update

helm upgrade --install traefik traefik/traefik --version 37.0.0 \
  --namespace traefik --create-namespace \
  --values starter/traefik-preview-values.yaml --wait
```

Kurulan kaynakları doğrula:

```bash
kubectl -n traefik get pods,service
kubectl get gatewayclass
```

Beklenen sonuç: Traefik Pod'u `Running`, Service'i `30088` NodePort ile görünür. `traefik` GatewayClass'ı listelenir.

---

## 3. Gateway ve HTTPRoute kaynaklarını tanımla

Aşağıdaki manifest (`starter/gateway-route.yaml`), Traefik Gateway dinleyicisini ve gelen alan adını `devops-app:80` servisine yönlendiren HTTPRoute kaynağını tanımlar:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: devops-app-gateway
  namespace: private-app
spec:
  gatewayClassName: traefik
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: Same
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: devops-app-route
  namespace: private-app
spec:
  parentRefs:
    - name: devops-app-gateway
  hostnames:
    - __APP_HOST__
  rules:
    - backendRefs:
        - name: devops-app
          port: 80
```

Kendi öğrenci DNS adını değişkene ata:

```bash
export STUDENT_ID="${STUDENT_ID:-$(hostname)}"
export APP_HOST="${STUDENT_ID}-app1.devopsatolyesi.com"
echo "Hedef Host: $APP_HOST"
```

Manifesti kopyala, `sed` ile host adını yerleştir ve uygula:

```bash
cp starter/gateway-route.yaml gateway-route.local.yaml
sed -i "s/__APP_HOST__/${APP_HOST}/g" gateway-route.local.yaml
kubectl apply -f gateway-route.local.yaml
```

Gateway ve HTTPRoute'un controller tarafından kabul edildiğini doğrula:

```bash
kubectl -n private-app wait --for=condition=Programmed gateway/devops-app-gateway --timeout=120s
kubectl -n private-app wait --for=condition=Accepted httproute/devops-app-route --timeout=120s
kubectl -n private-app get gateway,httproute
```

Beklenen sonuç: `devops-app-gateway` Programmed=True ve `devops-app-route` Accepted=True olur.

---

## 4. DNS'i değiştirmeden preview testi yap

Trafiği önce Traefik preview portuna (`30088`) göndererek HTTPRoute kurallarını test et:

```bash
curl -i -H "Host: ${APP_HOST}" http://127.0.0.1:30088/healthz
```

Beklenen sonuç: `HTTP/1.1 200 OK` ve `{"status": "UP", "application": "devops-app"}` döner. Bu sırada NGINX Ingress üzerinden gelen mevcut canlı trafik kesintisiz çalışmaya devam eder.

---

## 5. Gateway API'ye tam geçiş (Cutover) yap

Preview başarılı olduğuna göre NGINX Ingress controller'ı kaldırıp Traefik'i Kind kümesinin ana 80 portuna bağlayabiliriz.

Önce eski Ingress kaynağını ve NGINX Controller namespace'ini sil:

```bash
kubectl delete ingress -n private-app devops-app
kubectl delete namespace ingress-nginx
```

Aşağıdaki cutover ayarları (`starter/traefik-cutover-values.yaml`), Traefik Pod'unu doğrudan Kind control-plane içindeki `hostPort: 80` portuna bağlar:

```yaml
deployment:
  kind: Deployment
  replicas: 1
hostNetwork: false
nodeSelector:
  ingress-ready: "true"
tolerations:
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
service:
  enabled: false
ingressClass:
  enabled: false
providers:
  kubernetesIngress:
    enabled: false
  kubernetesGateway:
    enabled: true
gateway:
  enabled: false
gatewayClass:
  enabled: true
ports:
  web:
    port: 80
    exposedPort: 80
    hostPort: 80
```

Traefik'i cutover değerleriyle güncelle:

```bash
helm upgrade traefik traefik/traefik --version 37.0.0 \
  --namespace traefik --values starter/traefik-cutover-values.yaml --wait
```

Yeni Traefik Pod'unun hazır olduğunu ve canlı HTTPS trafiğinin başarıyla yanıt verdiğini doğrula:

```bash
kubectl -n traefik get pods -o wide
curl -i -k "https://${APP_HOST}/healthz"
```

Beklenen sonuç: Traefik control-plane içindeki `:80` portunu devralır; harici DNS ve Edge Nginx ayarları değişmeden `https://${APP_HOST}/healthz` adresi `200 OK` döner.
