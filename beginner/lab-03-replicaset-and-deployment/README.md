# Lab 03: Kendi Kendini Onarma (ReplicaSet ve Deployment)


## Amaç

Kubernetes'te Pod'lar "ölümlü" (ephemeral) nesnelerdir. Tek başına çalışan bir Pod çökerse, node kapanırsa veya elle silinirse Kubernetes onu **otomatik olarak yeniden başlatmaz**.

Bu laboratuvarda:
1. Tekil bir Pod'un neden self-healing (kendini onarma) yeteneğine sahip olmadığını,
2. **ReplicaSet** nesnesinin etiketler (`matchLabels`) ve kopyalar (`replicas`) üzerinden self-healing gücünü,
3. Üretim ortamlarında neden doğrudan ReplicaSet yerine **Deployment** kullanıldığını,
4. Deployment ile sürüm güncelleme (**Rollout**), durum takibi (**Rollout Status**) ve sorun anında bir önceki sürüme geri dönme (**Rollback / Undo**) adımlarını uygulamalı olarak öğreneceksiniz.

---

## Kullanılan Kavramlar

| Nesne / İşlem | Açıklama |
|---|---|
| **Self-Healing** | İstenen durum (desired state) ile mevcut durum (actual state) arasındaki farkı sürekli denetleyip eksilen Pod'ları otomatik tamamlama mekanizmasıdır. |
| **ReplicaSet** | Belirlenen sayıda Pod kopyasının her an ayakta kalmasını garanti eden alt düzey controller nesnesidir. |
| **Deployment** | ReplicaSet'leri arka planda yöneterek deklaratif güncellemeler, aşamalı geçişler (rolling update) ve geri alma (rollback) sağlayan üst düzey controller nesnesidir. |
| **Rollout Undo** | Hatalı veya istenmeyen bir güncelleme sonrasında tek komutla önceki çalışan sürüme dönme işlemidir. |

---

## Çalışma Dizini

```bash
cd ~/k8s-labs/beginner/lab-03-replicaset-and-deployment
```

---

## 1. İzole Namespace Oluşturma

```bash
kubectl create namespace beginner-deployments --dry-run=client -o yaml | kubectl apply -f -
```

---

## 2. Tekil Pod ile Controller Farkı (Self-Healing Eksikliğini Gör)

`starter/pod-alone.yaml` dosyasını inceleyin ve uygulayın:

```bash
kubectl apply -f starter/pod-alone.yaml -n beginner-deployments
kubectl get pods -n beginner-deployments
```

Pod `Running` duruma geldikten sonra Pod'u elle silin:

```bash
kubectl delete pod lone-pod -n beginner-deployments
kubectl get pods -n beginner-deployments
```

**Beklenen sonuç:** `No resources found`.  
Pod silindiğinde sonsuza kadar yok olur, çünkü arkasında onu gözeten hiçbir Controller (denetleyici) yoktur.

---

## 3. ReplicaSet ile Tanışma ve Self-Healing Kanıtı

`starter/replicaset.yaml` manifestini inceleyin:

```yaml
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: frontend-rs
  labels:
    app: frontend
spec:
  replicas: 3
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
        - name: nginx
          image: nginx:1.27-alpine
          ports:
            - containerPort: 80
```

Manifesti uygulayın:

```bash
kubectl apply -f starter/replicaset.yaml -n beginner-deployments
kubectl get replicaset,pods -n beginner-deployments
```

**Beklenen sonuç:** `frontend-rs` adlı 1 ReplicaSet ve 3 adet `frontend-rs-...` Pod'u listelenir.

### Self-Healing Testi

Pod'lardan birini rastgele silin ve anında Pod listesini kontrol edin:

```bash
POD_TO_DELETE=$(kubectl get pods -n beginner-deployments -l app=frontend -o jsonpath='{.items[0].metadata.name}')
echo "Silinen Pod: $POD_TO_DELETE"
kubectl delete pod "$POD_TO_DELETE" -n beginner-deployments
```

Hemen ardından Pod'ları listeleyin:

```bash
kubectl get pods -n beginner-deployments -l app=frontend
```

**Beklenen sonuç:**
Silinen Pod yok edilirken ReplicaSet anında yeni isimli bir Pod üreterek toplam sayıyı 3'te tutar!

ReplicaSet'i temizleyip bir sonraki adıma geçelim:

```bash
kubectl delete -f starter/replicaset.yaml -n beginner-deployments
```

---

## 4. ReplicaSet'ten Deployment'a Geçiş

ReplicaSet self-healing sağlar ancak sürüm güncelleme, kesintisiz geçiş ve sürüm geri alma gibi operasyonları yönetemez. Sektör standardı **Deployment** kullanmaktır.

`starter/deployment.yaml` manifestini inceleyin. Başlangıç olarak `nginx:1.26-alpine` imajını kullanıyoruz:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-deployment
  labels:
    app: web
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: nginx
          image: nginx:1.26-alpine
          ports:
            - containerPort: 80
```

Manifesti uygulayın:

```bash
kubectl apply -f starter/deployment.yaml -n beginner-deployments
kubectl get deployment,replicaset,pods -n beginner-deployments
```

**Beklenen sonuç:** 1 Deployment, Deployment'ın kendi oluşturduğu 1 ReplicaSet ve 3 Pod görüntülenir.

---

## 5. Imperative Ölçekleme (`kubectl scale`)

Trafik artışı durumunda Pod sayısını 3'ten 5'e çıkarın:

```bash
kubectl scale deployment web-deployment --replicas=5 -n beginner-deployments
kubectl get pods -n beginner-deployments -l app=web
```

**Beklenen sonuç:** Kısa sürede 5 Pod `Running` durumuna gelir.

İhtiyaç azaldığında tekrar 3'e indirin (scale-in):

```bash
kubectl scale deployment web-deployment --replicas=3 -n beginner-deployments
kubectl get pods -n beginner-deployments -l app=web
```

---

## 6. Canlı Sürüm Güncelleme (Rollout Update)

Uygulamanın imajını `nginx:1.26-alpine` sürümünden `nginx:1.27-alpine` sürümüne güncelleyin:

```bash
kubectl set image deployment/web-deployment nginx=nginx:1.27-alpine -n beginner-deployments
```

Güncellemenin aşamalı ilerleyişini canlı olarak izleyin:

```bash
kubectl rollout status deployment/web-deployment -n beginner-deployments
```

**Beklenen sonuç:**
```text
Waiting for deployment "web-deployment" rollout to finish: 1 out of 3 new replicas have been updated...
Waiting for deployment "web-deployment" rollout to finish: 2 out of 3 new replicas have been updated...
deployment "web-deployment" successfully rolled out
```

Yeni imajın Pod'lara uygulandığını doğrulayın:

```bash
kubectl get pods -n beginner-deployments -l app=web -o jsonpath='{.items[*].spec.containers[*].image}'; echo
```

**Beklenen sonuç:** Tüm Pod'larda `nginx:1.27-alpine` görünmelidir.

---

## 7. Güncelleme Geçmişi ve Geri Alma (Rollback / Undo)

Deployment üzerindeki tüm dağıtım revizyonlarını görüntüleyin:

```bash
kubectl rollout history deployment/web-deployment -n beginner-deployments
```

**Beklenen sonuç:** `REVISION 1` ve `REVISION 2` listelenir.

Yeni sürümde bir sorun olduğunu varsayalım ve anında bir önceki stabil sürüme dönelim:

```bash
kubectl rollout undo deployment/web-deployment -n beginner-deployments
```

Geri dönüş durumunu kontrol edin:

```bash
kubectl rollout status deployment/web-deployment -n beginner-deployments
```

Pod imajlarının tekrar `nginx:1.26-alpine` olduğunu doğrulayın:

```bash
kubectl get pods -n beginner-deployments -l app=web -o jsonpath='{.items[*].spec.containers[*].image}'; echo
```

---

## 8. Temizlik (Cleanup)

```bash
kubectl delete namespace beginner-deployments
```
