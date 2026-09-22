# Uygulamanı NGINX Ingress ile İnternete Aç

| Seviye | Tahmini Süre | Profil / Araçlar | Açık Portlar |
| --- | --- | --- | --- |
| Orta | 40 dk | kubectl, ingress-nginx | `19001` |

## Amaç

- Mevcut Edge Nginx ve Cloudflare ayarlarını değiştirmeden Ingress yönlendirmesi yapmak.
- `studentXX-app1.devopsatolyesi.com` hostname'ini ClusterIP Service'e bağlamak.

## Ön Koşullar

LAB-K8S-03'teki `devops-app` Deployment ve Service çalışmalıdır.

## Adım Adım Uygulama Rehberi

```bash
export STUDENT_ID="student01" # kendi öğrenci kodun
export APP_HOST="${STUDENT_ID}-app1.devopsatolyesi.com"
sed "s/__APP_HOST__/${APP_HOST}/g" labs/lab-04-nginx-ingress-routing/starter/ingress.yaml | kubectl apply -n private-app -f -
kubectl -n private-app get ingress
curl -k "https://${APP_HOST}/healthz"
curl -H "Host: ${APP_HOST}" "http://SUNUCU_IP:19001/healthz"
```

## Doğal Doğrulama ve Beklenen Sonuç

Her iki test de `status: UP` döndürmelidir. Host'suz fallback kuralı yoktur; Edge Nginx, Cloudflare ve mevcut öğrenci Nginx yapılandırması değiştirilmez.
