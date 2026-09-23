# * Uygulamanı NGINX Ingress ile İnternete Aç

## Amaç

Uygulamayı NGINX Ingress Controller kullanarak öğrenci DNS adı üzerinden internete ve dış dünyaya açmak.

## Kullanılan Kubernetes nesneleri

- **Ingress:** HTTP/HTTPS isteklerini (host ve path) doğru Service'e yönlendiren kural kümesidir.
- **Ingress Controller:** Ingress kurallarını okuyup trafiği yönlendiren ve yük dengeleyen Pod'lardır (NGINX tabanlı).
- **Service:** Ingress'in yönlendirdiği hedef uygulama servisidir.
- **Deployment & ConfigMap:** Ingress arkasında çalışan örnek backend uygulamasıdır.

## Çalışma dizini

```bash
cd ~/k8s-labs/lab-03-nginx-routing
```

> [!NOTE]
> Klasör adı `lab-03-nginx-ingress-routing` dizinindedir:
> ```bash
> cd ~/k8s-labs/lab-03-nginx-ingress-routing
> ```

## Erişim

- URL: `https://${APP_HOST}/healthz` (`APP_HOST` öğrenci DNS adındır)
- Doğrudan port erişimi: `http://127.0.0.1:19001/healthz` (Host header ile)
- Kimlik doğrulaması: yok

## * Doğrulanan senaryo

`19001` portuna doğru Host header ile ve öğrenci DNS adı üzerinden HTTPS ile
`devops-app` uygulamasından `{"status": "UP", "application": "devops-app"}` yanıtı alındı.

## Trafik mimarisi nasıl çalışır?

```text
İstemci (Tarayıcı / curl)
  → DNS / Cloudflare HTTPS (:443)
  → Host Edge Nginx
  → 127.0.0.1:19001 (Host Portu)
  → Kind control-plane :80 (Container Portu)
  → NGINX Ingress Controller Pod
  → private-app/devops-app Service (:80)
  → devops-app Pod
```

---

## 1. Uygulama ortamını ayağa kaldır

Bu lab tamamen bağımsızdır; önceki lablara ihtiyaç duymaz. Hazır starter manifesti ile namespace, backend uygulaması ve servisi tek komutla oluşturabilirsin.

```bash
kubectl apply -f starter/app.yaml
kubectl -n private-app rollout status deployment/devops-app
kubectl -n private-app get pods,service
```

Beklenen sonuç: `private-app` namespace'inde `devops-app` Deployment'ı, `Running` durumunda bir Pod ve `devops-app` Service'i listelenir.

---

## 2. NGINX Ingress Controller'ı kur

Ingress manifesti tek başına trafik taşımaz; kuralları okuyup uygulayan bir controller gerekir. Kind kümesi için hazırlanmış resmi NGINX Ingress Controller manifestini kur.

> [!NOTE]
> Kind ortamında Ingress Controller `control-plane` node'unun 80 portunu (`hostPort: 80`) kullanır. Kümede bu portu kullanan başka bir Ingress (örn. Traefik) varsa çakışmaması için önce kaldırılmalıdır:
> `helm uninstall traefik -n traefik 2>/dev/null || true`

```bash
kubectl apply -f https://github.com/kubernetes/ingress-nginx/raw/controller-v1.12.0/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=Ready pod \
  --selector=app.kubernetes.io/component=controller --timeout=180s
kubectl wait --namespace ingress-nginx \
  --for=condition=Complete job/ingress-nginx-admission-patch --timeout=180s
kubectl get pods -n ingress-nginx
```

Beklenen sonuç: `ingress-nginx-controller` Pod'u `Running` (1/1) durumuna gelir.

---

## 3. Kendi DNS adını değişkene ata

Sunucu adını otomatik almak için:

```bash
export STUDENT_ID="${STUDENT_ID:-$(hostname)}"
export APP_HOST="${STUDENT_ID}-app1.devopsatolyesi.com"
echo "Hedef Host: $APP_HOST"
```

Beklenen sonuç: `student101-app1.devopsatolyesi.com` (veya size atanan öğrenci numarası) görünür.

---

## 4. Ingress manifestini hazırla ve uygula

Starter dosyasının yerel bir kopyasını oluştur ve içindeki `__APP_HOST__` şablonunu kendi DNS adınla güncelle.

```bash
cp starter/ingress.yaml ingress.local.yaml
sed -i "s/__APP_HOST__/${APP_HOST}/g" ingress.local.yaml
cat ingress.local.yaml
```

Yerel Ingress manifestini cluster'a uygula:

```bash
kubectl apply -f ingress.local.yaml
kubectl -n private-app get ingress devops-app
kubectl -n private-app describe ingress devops-app
```

Beklenen sonuç: Ingress kuralında kendi hostname'iniz ve backend olarak `devops-app:80` görünür.

---

## 5. Doğrudan Kind giriş portunu test et (Port 19001)

Bu test DNS veya TLS katmanına girmeden, doğrudan Kind'in 19001 portuna Host header göndererek Ingress kuralını doğrular.

```bash
curl -i -H "Host: ${APP_HOST}" http://127.0.0.1:19001/healthz
```

Beklenen sonuç: `HTTP/1.1 200 OK` koduyla birlikte JSON çıktısı görünür:
```json
{"status": "UP", "application": "devops-app"}
```

---

## 6. Öğrenci DNS adı ve HTTPS ile test et

Bu test tüm internet akışını doğrular: DNS → Cloudflare SSL → Edge Nginx → Kind :80 → Ingress Controller → Service → Pod.

```bash
curl -i -k "https://${APP_HOST}/healthz"
```

Beklenen sonuç: `HTTP/2 200` kodu ve aynı JSON çıktısı döner:
```json
{"status": "UP", "application": "devops-app"}
```
