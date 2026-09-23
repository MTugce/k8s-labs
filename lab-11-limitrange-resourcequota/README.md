# * Namespace Kaynak Sınırı Koy: LimitRange ve ResourceQuota

## Amaç

LimitRange ile container'lara varsayılan kaynak değerleri atamayı ve ResourceQuota ile bir namespace'in toplam tüketebileceği CPU, bellek ve Pod sayısı bütçesini sınırlandırmayı öğrenmek.

## Kullanılan Kubernetes nesneleri

- **LimitRange:** Pod/container bazında varsayılan (default request/limit) ve izin verilen min/max kaynak sınırlarını tanımlar.
- **ResourceQuota:** Bir namespace'in toplamda harcayabileceği CPU, bellek ve oluşturulabilecek azami nesne (Pod) sayısını sınırlar.
- **Namespace:** Yönetişim (governance) kurallarının uygulandığı izole çalışma alanıdır (`governance-lab`).

## Çalışma dizini

```bash
cd ~/k8s-labs/lab-11-limitrange-resourcequota
```

## * Doğrulanan senaryo

LimitRange, kaynak belirtmeyen bir pod'a otomatik olarak 100m CPU ve 64Mi bellek request'i ekledi. ResourceQuota toplam pod sayısını 4 ile sınırladığı için, 5 replica isteyen ikinci bir Deployment'ın kotayı aşan pod'ları Kubernetes tarafından reddedildi (`exceeded quota: lab-quota`).

---

## 1. Namespace, LimitRange ve ResourceQuota Politikalarını İncele ve Uygula

Aşağıdaki manifest (`starter/governance.yaml`), `governance-lab` namespace'ini ve namespace üzerinde geçerli olacak sınırları tanımlar:
- **LimitRange:** Kaynak belirtmeyen container'lara otomatik `100m CPU / 64Mi RAM` talebi ekler.
- **ResourceQuota:** Namespace genelinde en fazla 4 Pod ve en fazla 500m CPU request'i kullanımına izin verir.

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: governance-lab
---
apiVersion: v1
kind: LimitRange
metadata:
  name: lab-defaults
  namespace: governance-lab
spec:
  limits:
    - type: Container
      defaultRequest:
        cpu: 100m
        memory: 64Mi
      default:
        cpu: 300m
        memory: 128Mi
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: lab-quota
  namespace: governance-lab
spec:
  hard:
    pods: "4"
    requests.cpu: "500m"
    limits.cpu: "1"
```

Politikaları cluster'a uygula ve tanımları doğrula:

```bash
kubectl apply -f starter/governance.yaml
kubectl -n governance-lab get limitrange,resourcequota
kubectl -n governance-lab describe limitrange lab-defaults
kubectl -n governance-lab describe resourcequota lab-quota
```

Beklenen sonuç: LimitRange varsayılan request/limit değerlerini, ResourceQuota ise `hard: pods: 4, requests.cpu: 500m` kurallarını gösterir.

---

## 2. Kaynak Belirtmeyen Normal Deployment Oluştur

Aşağıdaki manifestte (`starter/allowed-deployment.yaml`) container için hiçbir `resources` alanı tanımlanmamıştır:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: allowed-app
  namespace: governance-lab
spec:
  replicas: 1
  selector:
    matchLabels:
      app: allowed-app
  template:
    metadata:
      labels:
        app: allowed-app
    spec:
      containers:
        - name: web
          image: nginx:1.27-alpine
```

Manifesti uygula ve oluşan Pod'u incele:

```bash
kubectl apply -f starter/allowed-deployment.yaml
kubectl -n governance-lab rollout status deployment/allowed-app
kubectl -n governance-lab describe pod -l app=allowed-app
```

Beklenen sonuç: Pod başarıyla çalışır. `describe` çıktısındaki **Requests** ve **Limits** bölümlerinde `Limits`'in eklediği `cpu: 100m`, `memory: 64Mi` otomatik değerleri görünür.

---

## 3. Kotayı Aşan Deployment'ı Dene (Hata Senaryosu)

Aşağıdaki manifest (`starter/rejected-deployment.yaml`) 5 adet replica talep eder. Ancak namespace'in toplam pod kotası 4'tür (ve 1 pod zaten çalışmaktadır):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rejected-app
  namespace: governance-lab
spec:
  replicas: 5
  selector:
    matchLabels:
      app: rejected-app
  template:
    metadata:
      labels:
        app: rejected-app
    spec:
      containers:
        - name: web
          image: nginx:1.27-alpine
```

Manifesti uygula:

```bash
kubectl apply -f starter/rejected-deployment.yaml
kubectl -n governance-lab get deployment,replicaset,pods
```

ReplicaSet olaylarını (Events) incele:

```bash
kubectl -n governance-lab describe replicaset -l app=rejected-app
```

Beklenen sonuç: Pod kotasında kalan 3 adet boşluk kadar pod başlatılabilir, ancak 5 replica tamamlanamaz. ReplicaSet loglarında `failed quota: lab-quota: exceeded quota: pods` veya `requests.cpu` hatası açıkça görülür.

---

## 4. Tüketilen Kaynak Bütçesini İncele

```bash
kubectl -n governance-lab describe resourcequota lab-quota
```

Beklenen sonuç: `Used` ve `Hard` sütunlarında izin verilen maksimum limitlerin doldurulduğu ve aşılmasına izin verilmediği raporlanır.
