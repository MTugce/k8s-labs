# Lab 06: Temel Depolama (emptyDir, PV ve Dynamic PVC)


## Amaç

Konteynerlerin kök dosya sistemi geçicidir (ephemeral). Bir konteyner çöktüğünde veya Pod yeniden başlatıldığında, içerisine yazılan tüm dosyalar silinir. Veritabanı ve durum bilgisi (state) taşıyan uygulamalarda verinin Pod yaşam döngüsünden bağımsız olarak korunması gerekir.

Bu laboratuvarda:
1. Aynı Pod içindeki konteynerler arasında geçici dosya paylaşımı sağlayan **emptyDir** birimini,
2. Kalıcı depolama mimarisini oluşturan **PersistentVolume (PV)** ve **PersistentVolumeClaim (PVC)** ilişkisini,
3. Kind cluster'ındaki hazır `standard` StorageClass ile **dinamik provizyon (dynamic provisioning)** yapmayı,
4. Pod silinse dahi diske yazılan verinin yeni Pod tarafından aynen korunduğunu uygulamalı olarak kanıtlayacaksınız.

---

## Kullanılan Kavramlar

| Nesne / Kavram | Açıklama |
|---|---|
| **emptyDir** | Pod oluşturulduğunda tahsis edilen ve Pod silindiğinde silinen geçici bir birimdir; aynı Pod içindeki konteynerlerin dosya paylaşımı için idealdir. |
| **PersistentVolume (PV)** | Cluster'daki gerçek bir depolama kaynağını (yerel disk, ağ diski, bulut diski) temsil eden cluster düzeyinde nesnedir. |
| **PersistentVolumeClaim (PVC)** | Bir kullanıcının/uygulamanın belirli boyutta (örn. 1Gi) ve erişim modunda disk talep etmesidir. |
| **StorageClass & Dynamic Provisioning** | PVC oluşturulduğunda arkada otomatik olarak uygun PV oluşturan mekanizmadır. |

---

## Çalışma Dizini

```bash
cd ~/k8s-labs/beginner/lab-06-storage-emptydir-and-pvc
```

---

## 1. İzole Namespace Oluşturma

```bash
kubectl create namespace beginner-storage --dry-run=client -o yaml | kubectl apply -f -
```

---

## 2. Pod İçi Geçici Depolama (`emptyDir`)

`starter/pod-emptydir.yaml` manifestini inceleyin:
- `writer-agent`: Her 2 saniyede bir paylaşılan `/html/index.html` dosyasına güncel zamanı yazar.
- `reader-web`: Aynı diski `/usr/share/nginx/html` konumuna salt-okunur bağlayarak web üzerinden sunar.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: shared-volume-pod
  labels:
    app: shared-volume
spec:
  containers:
    - name: reader-web
      image: nginx:1.27-alpine
      ports:
        - containerPort: 80
      volumeMounts:
        - name: shared-html
          mountPath: /usr/share/nginx/html
          readOnly: true
    - name: writer-agent
      image: alpine:3.21
      command: ["/bin/sh", "-c"]
      args:
        - |
          while true; do
            echo "<h1>Guncel Zaman: $(date)</h1>" > /html/index.html;
            sleep 2;
          done
      volumeMounts:
        - name: shared-html
          mountPath: /html
  volumes:
    - name: shared-html
      emptyDir: {}
```

Manifesti uygulayın:

```bash
kubectl apply -f starter/pod-emptydir.yaml -n beginner-storage
kubectl wait --for=condition=Ready pod/shared-volume-pod -n beginner-storage --timeout=60s
```

Web konteynerine istek atarak yazar konteynerin ürettiği dinamik içeriği okuyun:

```bash
kubectl exec -n beginner-storage shared-volume-pod -c reader-web -- wget -qO- http://localhost:80
```

**Beklenen sonuç:** `<h1>Guncel Zaman: Mon Sep 28 ...</h1>`  
Konteynerler arasında geçici veri aktarımı başarıyla doğrulanmıştır.

Pod'u temizleyelim:

```bash
kubectl delete pod shared-volume-pod -n beginner-storage
```

---

## 3. Dinamik Kalıcı Depolama Talebi (PVC)

`starter/pvc.yaml` manifesti, Kind'in varsayılan `standard` StorageClass'ından 1Gi boyutunda bir kalıcı disk talep eder:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: standard
  resources:
    requests:
      storage: 1Gi
```

Manifesti uygulayın:

```bash
kubectl apply -f starter/pvc.yaml -n beginner-storage
kubectl get pvc app-data-pvc -n beginner-storage
```

**Beklenen sonuç:**
PVC `STATUS` değeri `Bound` olur ve arka planda otomatik olarak `pvc-...` adında bir PV üretilip eşleştirilir:
```text
NAME           STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
app-data-pvc   Bound    pvc-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx   1Gi        RWO            standard       5s
```

Oluşan kalıcı diski (PV) görüntüleyin:

```bash
kubectl get pv
```

---

## 4. PVC'yi Pod'a Bağlama ve Veri Yazma

`starter/app-storage.yaml` manifesti diski `/data` dizinine bağlar:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: storage-pod-1
  labels:
    app: persistent-test
spec:
  containers:
    - name: app
      image: alpine:3.21
      command: ["sh", "-c", "sleep 3600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: app-data-pvc
```

Manifesti uygulayın:

```bash
kubectl apply -f starter/app-storage.yaml -n beginner-storage
kubectl wait --for=condition=Ready pod/storage-pod-1 -n beginner-storage --timeout=60s
```

Kalıcı diske bir metin dosyası kaydedin:

```bash
kubectl exec -n beginner-storage storage-pod-1 -- sh -c 'echo "Bu veri kalici diskte saklaniyor - Tarih: $(date)" > /data/not.txt'
kubectl exec -n beginner-storage storage-pod-1 -- cat /data/not.txt
```

---

## 5. Veri Kalıcılığını Kanıtlama (Pod Silinse de Veri Kalır)

Şimdi `storage-pod-1` Pod'unu tamamen silin:

```bash
kubectl delete pod storage-pod-1 -n beginner-storage
kubectl get pods -n beginner-storage
```

Aynı PVC'yi bağlayan yeni bir Pod (`storage-pod-2`) başlatalım:

```bash
kubectl run storage-pod-2 \
  --image=alpine:3.21 \
  --restart=Never \
  -n beginner-storage \
  --overrides='{
    "spec": {
      "containers": [{
        "name": "app",
        "image": "alpine:3.21",
        "command": ["sh", "-c", "sleep 3600"],
        "volumeMounts": [{"name": "data", "mountPath": "/data"}]
      }],
      "volumes": [{
        "name": "data",
        "persistentVolumeClaim": {"claimName": "app-data-pvc"}
      }]
    }
  }'
```

Yeni Pod'un hazır olmasını bekleyin:

```bash
kubectl wait --for=condition=Ready pod/storage-pod-2 -n beginner-storage --timeout=60s
```

Eski Pod silinmiş olmasına rağmen dosyanın korunduğunu yeni Pod içinden okuyarak kanıtlayın:

```bash
kubectl exec -n beginner-storage storage-pod-2 -- cat /data/not.txt
```

**Beklenen sonuç:**
```text
Bu veri kalici diskte saklaniyor - Tarih: ...
```

---

## 6. Temizlik (Cleanup)

```bash
kubectl delete namespace beginner-storage
```
Namespace silindiğinde PVC ve ona bağlı dinamik PV otomatik olarak temizlenir.
