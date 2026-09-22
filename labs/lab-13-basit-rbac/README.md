# Kubernetes'te Basit RBAC: ServiceAccount, Role ve RoleBinding

| Seviye | Tahmini Süre | Profil / Araçlar | Açık Portlar |
| --- | --- | --- | --- |
| Orta | 40 dk | kubectl | — |

## Bu labda ne yapacaksın?

Bir ServiceAccount oluşturacak, yalnızca kendi namespace'indeki Pod'ları listeleme izni veren Role yazacak ve RoleBinding ile bu izni bağlayacaksın. Sonra izinli ve izinsiz işlemleri `kubectl auth can-i` ile kanıtlayacaksın.

## RBAC akışı

```text
ServiceAccount  →  Role  →  RoleBinding  →  İzinli işlem
```

- ServiceAccount, Pod veya uygulamanın Kubernetes API kimliğidir.
- Role, bir namespace içindeki izin listesidir.
- RoleBinding, Role'ü belirli ServiceAccount'a bağlar.

## 1. ServiceAccount ve Role'ü oluştur

```bash
kubectl apply -f labs/lab-13-basit-rbac/starter/rbac.yaml
kubectl -n rbac-lab get serviceaccount,role,rolebinding
kubectl -n rbac-lab describe role pod-reader
```

Beklenen sonuç: `pod-reader` Role'ünde yalnızca `get` ve `list` fiilleri, yalnızca `pods` kaynağı için görünür.

## 2. ServiceAccount'ın kendi namespace'indeki iznini test et

`--as` parametresi, komutu ServiceAccount kimliğiyle denemeyi sağlar.

```bash
kubectl auth can-i list pods \
  --as=system:serviceaccount:rbac-lab:pod-reader \
  --namespace=rbac-lab
```

Beklenen sonuç: `yes`.

## 3. Başka namespace'e erişimin reddedildiğini göster

Role namespace kapsamlıdır. Aynı ServiceAccount'ın `first-app` namespace'indeki Pod'ları listelemesine izin yoktur.

```bash
kubectl auth can-i list pods \
  --as=system:serviceaccount:rbac-lab:pod-reader \
  --namespace=first-app
kubectl auth can-i delete pods \
  --as=system:serviceaccount:rbac-lab:pod-reader \
  --namespace=rbac-lab
```

Beklenen sonuç: iki komut da `no` döndürür. ServiceAccount yalnızca izin verilen namespace ve fiillerle çalışabilir.

## 4. Gerçek API çağrısını dene

```bash
kubectl get pods --as=system:serviceaccount:rbac-lab:pod-reader -n rbac-lab
kubectl get pods --as=system:serviceaccount:rbac-lab:pod-reader -n first-app
```

Beklenen sonuç: ilk komut Pod listesini döndürür; ikinci komut `Forbidden` hatası verir. Bu labda RBAC'ın Kubernetes API erişimini nasıl sınırladığını uygulamalı gördün.
