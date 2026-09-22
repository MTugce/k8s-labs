# Uygulamanı NGINX Ingress ile İnternete Aç

Bu labı şu klasörde uygulayacaksın:

```bash
cd ~/k8s-labs/lab-03-nginx-ingress-routing
```

## Bu labda ne yapacaksın?

Önceki labdaki `devops-app` Service'ini, mevcut öğrenci DNS adıyla erişilebilir yapacaksın. Edge Nginx, Cloudflare veya host Nginx yapılandırmasına hiçbir değişiklik yapmayacaksın.

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

## 1. NGINX Ingress controller kur

Ingress manifesti tek başına trafik taşımaz; onu okuyan bir controller gerekir. Bu controller yalnızca Kind cluster içinde çalışır, hosttaki Edge Nginx'e dokunmaz.

```bash
kubectl apply -f https://github.com/kubernetes/ingress-nginx/raw/controller-v1.12.0/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=Ready pod \
  --selector=app.kubernetes.io/component=controller --timeout=180s
kubectl get pods -n ingress-nginx
```

Beklenen sonuç: `ingress-nginx-controller` Pod'u `Running` görünür.

## 2. Uygulamanın hazır olduğunu doğrula

Ingress Pod'a değil Service'e yönlendirir. Bu nedenle önce Service ve Pod'lar çalışıyor olmalı.

```bash
kubectl -n private-app get deployment,pods,service
```

Beklenen sonuç: `devops-app` Deployment'ında iki hazır Pod ve `devops-app` Service'i görünür.

## 3. Kendi DNS adını değişkene yaz

`student01` yerine sana verilen öğrenci kodunu kullan.

```bash
export STUDENT_ID="student01"
export APP_HOST="${STUDENT_ID}-app1.devopsatolyesi.com"
echo "$APP_HOST"
```

Beklenen sonuç: `student01-app1.devopsatolyesi.com` görünür.

## 4. Ingress manifestini uygula

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

## 5. Önce doğrudan Kind girişini test et

Bu test DNS veya TLS katmanı olmadan yalnızca host header ile Ingress kuralını doğrular.

```bash
curl -H "Host: ${APP_HOST}" http://SUNUCU_IP:19001/healthz
```

Beklenen sonuç: JSON yanıtta `status: UP` görünür.

## 6. Öğrenci DNS adıyla test et

Bu test tüm akışı kullanır: DNS → Edge Nginx → Kind → Ingress → Service → Pod.

```bash
curl -k "https://${APP_HOST}/healthz"
```

Beklenen sonuç: yine `status: UP` görünür.

Bu manifestte host'suz fallback kuralı yoktur. Böylece doğrudan `19001` portuna yanlış hostname ile gelen trafik başka uygulamaların yerine bu uygulamaya yönlenmez.
