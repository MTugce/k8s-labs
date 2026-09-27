# * Kubernetes'te Basit RBAC: ServiceAccount, Role ve RoleBinding

> **Seviye:** Orta
> **Tahmini süre:** 40–50 dakika
> **Lab Kapsamı:** Seviyeye göre

## Amaç

Kubernetes Rol Tabanlı Erişim Kontrolü (RBAC) mekanizmasını kullanarak; `ServiceAccount`, `Role` ve `RoleBinding` nesneleriyle en az yetki (least privilege) ilkesine uygun güvenli erişim tanımlamayı öğrenmek.

## Kullanılan Kubernetes nesneleri

- **ServiceAccount:** Kubernetes API'sine erişecek pod veya servis kimliğidir (`pod-reader`).
- **Role:** Belirli bir namespace içindeki izin kuralları listesidir (örn. sadece Pod'ları `get`, `list` edebilme).
- **RoleBinding:** Tanımlanan Role ile ServiceAccount kimliğini birbirine bağlayan köprüdür.

## Çalışma dizini

```bash
cd ~/k8s-labs/intermediate/lab-06-rbac
```

## RBAC mimarisi

```text
ServiceAccount (Kimlik)  →  RoleBinding (Bağlantı)  →  Role (İzinler)  →  Kubernetes API
```

---

## 1. RBAC Manifestini İncele ve Uygula

Aşağıdaki manifest (`starter/rbac.yaml`), `rbac-lab` namespace'ini, bu alanda sadece Pod'ları okuma yetkisi veren `pod-reader` Role'ünü ve bunu `pod-reader` ServiceAccount kimliğine bağlayan RoleBinding nesnesini tanımlar:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: rbac-lab
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: pod-reader
  namespace: rbac-lab
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: rbac-lab
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pod-reader-binding
  namespace: rbac-lab
subjects:
  - kind: ServiceAccount
    name: pod-reader
    namespace: rbac-lab
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: pod-reader
```

Manifesti cluster'a uygula:

```bash
kubectl apply -f starter/rbac.yaml
kubectl -n rbac-lab get serviceaccount,role,rolebinding
kubectl -n rbac-lab describe role pod-reader
```

Beklenen sonuç: `pod-reader` Role'ünde yalnızca `get` ve `list` fiillerinin `pods` kaynağına izin verdiği doğrulanır.

---

## 2. Kendi Namespace'indeki İzni Test Et (`kubectl auth can-i`)

`--as` parametresi, komutu doğrudan ilgili ServiceAccount kimliğinin gözünden denememizi sağlar:

```bash
kubectl auth can-i list pods \
  --as=system:serviceaccount:rbac-lab:pod-reader \
  --namespace=rbac-lab
```

Beklenen sonuç: `yes`.

---

## 3. Yetki Sınırlarını Test Et (İzin Verilmeyen İşlemler)

Rol namespace kapsamlıdır (namespaced). Aynı ServiceAccount'ın başka bir namespace'teki pod'ları görmesine veya kendi namespace'inde pod silmesine izin yoktur:

```bash
# Başka namespace'teki pod'ları listelemeyi dene:
kubectl auth can-i list pods \
  --as=system:serviceaccount:rbac-lab:pod-reader \
  --namespace=first-app

# Kendi namespace'inde pod silmeyi dene:
kubectl auth can-i delete pods \
  --as=system:serviceaccount:rbac-lab:pod-reader \
  --namespace=rbac-lab
```

Beklenen sonuç: İki sorgu da `no` döndürür.

---

## 4. Gerçek API Çağrısı ile Yetkiyi Doğrula

Yetki sorgulamasının ardından doğrudan gerçek API komutunu deneyelim:

```bash
# İzinli işlem:
kubectl get pods --as=system:serviceaccount:rbac-lab:pod-reader -n rbac-lab

# İzin verilmeyen işlem:
kubectl get pods --as=system:serviceaccount:rbac-lab:pod-reader -n first-app
```

Beklenen sonuç:
- İlk komut pod listesini (veya `No resources found`) başarıyla döner.
- İkinci komut Kubernetes API'sinden `Error from server (Forbidden): pods is forbidden` hatası alır.

## Başarı kriterleri

- ServiceAccount, Role ve RoleBinding ilişkisini açıklayabiliyorsunuz.
- İzinli `list pods` işlemi `yes` döndürdü.
- Namespace dışı erişim ve Pod silme işlemleri reddedildi.

## Temizlik

```bash
kubectl delete namespace rbac-lab
```
