# Kind Kümeni Kur ve Kubectl ile Başla

| Seviye | Tahmini Süre | Profil / Araçlar | Açık Portlar |
| --- | --- | --- | --- |
| Başlangıç | 35 dk | Docker, Kind, kubectl | `19001-19003`, `30086-30089` |

## Amaç

- Azure öğrenci slotlarıyla çakışmayan Kind kümesini başlatmak.
- Pod oluşturma, inceleme, log ve `exec` komutlarını kullanmak.

## Ön Koşullar

```bash
docker info
kind version
kubectl version --client
```

`80`, `443`, `18081`, `18443`, `30080-30085` ve `30090` bu labın alanı değildir. Kurulum yalnızca `19001-19003` ve `30086-30089` için kontrol yapar.

## Adım Adım Uygulama Rehberi

```bash
./platform/setup-kind-cluster.sh
kubectl get nodes -o wide
kubectl run first-web --image=nginx:1.27-alpine --labels='app=first-web,lab=01'
kubectl get pod first-web --show-labels
kubectl describe pod first-web
kubectl exec first-web -- nginx -v
kubectl delete pod first-web
```

## Doğal Doğrulama ve Beklenen Sonuç

```bash
kubectl get nodes
kubectl get pods
```

Üç node `Ready` olmalı, `first-web` silinmiş olmalıdır.
