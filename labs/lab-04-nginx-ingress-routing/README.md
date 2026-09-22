# Uygulamanı NGINX Ingress ile İnternete Aç

| Seviye | Tahmini Süre | Profil / Araçlar | Açık Portlar |
| --- | --- | --- | --- |
| Orta | 45 dk | kubectl, ingress-nginx | `19001` |

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

## 1. Uygulamanın hazır olduğunu doğrula

Ingress Pod'a değil Service'e yönlendirir. Bu nedenle önce Service ve Pod'lar çalışıyor olmalı.

```bash
kubectl -n private-app get deployment,pods,service
```

Beklenen sonuç: `devops-app` Deployment'ında iki hazır Pod ve `devops-app` Service'i görünür.

## 2. Kendi DNS adını değişkene yaz

`student01` yerine sana verilen öğrenci kodunu kullan.

```bash
export STUDENT_ID="student01"
export APP_HOST="${STUDENT_ID}-app1.devopsatolyesi.com"
echo "$APP_HOST"
```

Beklenen sonuç: `student01-app1.devopsatolyesi.com` görünür.

## 3. Ingress manifestini uygula

Manifestteki `__APP_HOST__` alanı terminaldeki DNS adıyla değiştirilir. Dosyanın kendisi değiştirilmez; her öğrenci aynı starter dosyasını kullanır.

```bash
sed "s/__APP_HOST__/${APP_HOST}/g" labs/lab-04-nginx-ingress-routing/starter/ingress.yaml | kubectl apply -n private-app -f -
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
