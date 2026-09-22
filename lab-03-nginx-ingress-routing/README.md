# * Uygulamanı NGINX Ingress ile İnternete Aç

## Amaç

Uygulamayı NGINX Ingress ile öğrenci DNS adı üzerinden erişilebilir yapmak.

## Kullanılan Kubernetes nesneleri

- **Ingress:** Hostname ve path isteğini bir Service'e yönlendiren kuraldır.
- **Ingress Controller:** Ingress kurallarını okuyup trafiği gerçekten ileten Pod'lardır.
- **Service:** Ingress'in eriştiği uygulama hedefidir.

## Çalışma dizini

```bash
cd ~/k8s-labs/lab-03-nginx-ingress-routing
```

## Erişim

- URL: `https://${APP_HOST}/healthz` (`APP_HOST` kendi öğrenci DNS adındır.)
- Kimlik doğrulaması: yok

## * Doğrulanan senaryo

`19001` portuna doğru Host header ile ve öğrenci DNS adı üzerinden HTTPS ile
`devops-app` uygulamasından `status: UP` yanıtı alındı.

## Başlamadan önce Lab 2 kontrolü

Bu lab yeni uygulama oluşturmaz; Lab 2'de çalıştırdığın `devops-app` Deployment ve Service'ini kullanır. Önce namespace'in var olduğunu kontrol et.

```bash
kubectl get namespace private-app
```

Sonra uygulamanın Deployment, Pod ve Service kaynaklarını kontrol et.

```bash
kubectl -n private-app get deployment,pods,service
```

Beklenen sonuç: `devops-app` Deployment'ı, en az bir `Running` Pod ve `devops-app` Service'i görünür.

`private-app` bulunamazsa veya `No resources found` görürsen bu labda ilerleme. Lab 2'ye dön, final Deployment adımını tamamla ve Pod'ların `Running` olduğunu gör.

## Trafik nasıl gelir?

```text
student01-app1.devopsatolyesi.com
  → Edge Nginx :443
  → 127.0.0.1:19001
  → Kind control-plane :80
  → NGINX Ingress
  → private-app/devops-app Service
  → Pod
```

`student01-app1...` doğru ad biçimidir. `student01.app1...` kullanma.

## Ingress mimarisi

```text
İstemci → DNS / Edge Nginx → 19001 → Kind control-plane :80
        → ingress-nginx Controller → Ingress kuralı → Service → Pod
```

**Ingress**, hostname ve path eşleştirmesini tanımlayan Kubernetes kaynağıdır.
Tek başına trafik iletmez. **ingress-nginx Controller** bu kuralı okuyup isteği
doğru Service'e gönderir. Edge Nginx ve Cloudflare bu labın dışında kalır;
değiştirilmez.

## 1. NGINX Ingress controller kur

Ingress manifesti tek başına trafik taşımaz; onu okuyan bir controller gerekir. Bu controller yalnızca Kind cluster içinde çalışır, hosttaki Edge Nginx'e dokunmaz.

```bash
kubectl apply -f https://github.com/kubernetes/ingress-nginx/raw/controller-v1.12.0/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=Ready pod \
  --selector=app.kubernetes.io/component=controller --timeout=180s
kubectl wait --namespace ingress-nginx \
  --for=condition=Complete job/ingress-nginx-admission-patch --timeout=180s
kubectl get pods -n ingress-nginx
```

Beklenen sonuç: `ingress-nginx-controller` Pod'u `Running` görünür. İkinci
bekleme komutu Ingress doğrulama webhook'unu hazırlar; tamamlanmadan Ingress
manifesti uygulanırsa bağlantı hatası alınabilir.

## 2. Kendi DNS adını değişkene yaz

`student01` yerine sana verilen öğrenci kodunu kullan.

```bash
export STUDENT_ID="student01"
export APP_HOST="${STUDENT_ID}-app1.devopsatolyesi.com"
echo "$APP_HOST"
```

Beklenen sonuç: `student01-app1.devopsatolyesi.com` görünür.

## 3. Ingress manifestini uygula

Starter dosyasının yerel kopyasını oluştur. Böylece ortak starter dosyası değişmeden yalnızca kendi DNS adını yazarsın.

```bash
cp starter/ingress.yaml ingress.local.yaml
```

`ingress.local.yaml` dosyasını aç. `host: __APP_HOST__` satırını `echo "$APP_HOST"` komutunun gösterdiği DNS adıyla değiştir ve kaydet.

```bash
nano ingress.local.yaml
```

Yerel Ingress manifestini uygula ve oluşan kuralı kontrol et.

```bash
kubectl apply -n private-app -f ingress.local.yaml
kubectl -n private-app get ingress
kubectl -n private-app describe ingress devops-app
```

Beklenen sonuç: Ingress kurallarında kendi hostname'in ve backend olarak `devops-app:80` görünür.

## 4. Önce doğrudan Kind girişini test et

Bu test DNS veya TLS katmanı olmadan yalnızca host header ile Ingress kuralını doğrular.

```bash
curl -H "Host: ${APP_HOST}" http://SUNUCU_IP:19001/healthz
```

Beklenen sonuç: JSON yanıtta `status: UP` görünür.

## 5. Öğrenci DNS adıyla test et

Bu test tüm akışı kullanır: DNS → Edge Nginx → Kind → Ingress → Service → Pod.

```bash
curl -k "https://${APP_HOST}/healthz"
```

Beklenen sonuç: yine `status: UP` görünür.

Bu manifestte host'suz fallback kuralı yoktur. Böylece doğrudan `19001` portuna yanlış hostname ile gelen trafik başka uygulamaların yerine bu uygulamaya yönlenmez.
