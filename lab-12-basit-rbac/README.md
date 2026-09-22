# * Kubernetes'te Basit RBAC: ServiceAccount, Role ve RoleBinding

Bu labı şu klasörde uygulayacaksın:

```bash
cd ~/k8s-labs/lab-12-basit-rbac
```

## Bu labda ne yapacaksın?

Bir ServiceAccount oluşturacak, yalnızca kendi namespace'indeki Pod'ları listeleme izni veren Role yazacak ve RoleBinding ile bu izni bağlayacaksın. Sonra izinli ve izinsiz işlemleri `kubectl auth can-i` ile kanıtlayacaksın.

## * Doğrulanan senaryo

`pod-reader`, kendi namespace'inde Pod listeleme izni aldı (`yes`). Başka
namespace'te listeleme ve Pod silme denemeleri `no` döndü.

## RBAC akışı

```text
ServiceAccount  →  Role  →  RoleBinding  →  İzinli işlem
```

- ServiceAccount, Pod veya uygulamanın Kubernetes API kimliğidir.
- Role, bir namespace içindeki izin listesidir.
- RoleBinding, Role'ü belirli ServiceAccount'a bağlar.

## 1. ServiceAccount ve Role'ü oluştur

```bash
kubectl apply -f ~/k8s-labs/lab-12-basit-rbac/starter/rbac.yaml
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
