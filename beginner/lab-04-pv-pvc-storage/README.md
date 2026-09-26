# * Veriyi Kaybetme: PV, PVC, Static ve Dynamic Storage

> **Seviye:** Başlangıç / Orta
> **Tahmini süre:** 55–70 dakika
> **Ön koşul:** Beginner Lab 2
> **Eğitim durumu:** Zorunlu

## Amaç

Static ve dynamic PV/PVC kalıcı depolama akışlarını aynı cluster üzerinde karşılaştırmalı olarak öğrenmek.

## Kullanılan Kubernetes nesneleri

- **PV (PersistentVolume):** Cluster'ın sunduğu gerçek disk kaynağıdır.
- **PVC (PersistentVolumeClaim):** Uygulamanın talep ettiği disk alanıdır.
- **StorageClass:** Dynamic PV'yi otomatik oluşturacak depolama eklentisini (provisioner) seçer.
- **Pod:** PVC'ye bağlanıp veriyi okuyan veya yazan iş yüküdür.

## Çalışma dizini

```bash
cd ~/k8s-labs/beginner/lab-04-pv-pvc-storage
```

---

## 1. Dynamic storage provisioner'ını kur

Static PV'yi küme yöneticisi önceden elle oluşturur. Dynamic depolamada ise PVC açıldığında diski otomatik oluşturan bir provisioner gerekir.

Kind kümesinde kullanılan `local-path` provisioner'ı kur:

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.36/deploy/local-path-storage.yaml
kubectl wait -n local-path-storage --for=condition=Available deployment/local-path-provisioner --timeout=180s
kubectl get storageclass local-path
```

Beklenen sonuç: `local-path` StorageClass'ı listelenir.

---

## 2. Namespace oluştur

```bash
kubectl create namespace storage-lab --dry-run=client -o yaml | kubectl apply -f -
```

---

## 3. Static PV ve PVC'yi incele ve bağla

Aşağıdaki manifest (`starter/static-pv-pvc.yaml`), Kind node'una bağlanmış `/mnt/k8s-labs/static-pv` host dizinini 1Gi boyutunda bir PV olarak tanımlar. Altındaki PVC ise `volumeName: static-pv` diyerek doğrudan bu diski talep eder:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: static-pv
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  storageClassName: ""
  hostPath:
    path: /mnt/k8s-labs/static-pv
    type: DirectoryOrCreate
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: static-pvc
spec:
  volumeName: static-pv
  storageClassName: ""
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

Manifesti uygula ve bağ durumunu kontrol et:

```bash
kubectl apply -n storage-lab -f starter/static-pv-pvc.yaml
kubectl get pv static-pv
kubectl -n storage-lab get pvc static-pvc
```

Beklenen sonuç: PV ve PVC durumu `Bound` olur (`storageClassName: ""` statik bağlamayı temsil eder).

---

## 4. Diske veri yaz (Writer Pod)

Aşağıdaki Pod (`starter/writer.yaml`), `static-pvc` diskini `/data` dizinine bağlar ve içine anlık tarih/saat damgasını yazar:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: writer
spec:
  restartPolicy: Never
  containers:
    - name: writer
      image: busybox:1.37
      command:
        - sh
        - -c
        - "date > /data/message.txt; cat /data/message.txt"
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: static-pvc
```

Pod'u çalıştır ve log çıktısını oku:

```bash
kubectl apply -n storage-lab -f starter/writer.yaml
kubectl -n storage-lab wait --for=jsonpath='{.status.phase}'=Succeeded pod/writer --timeout=90s
kubectl -n storage-lab logs writer
```

Beklenen sonuç: Loglarda diske yazılan tarih bilgisi görünür.

---

## 5. Pod silinse de verinin kaldığını kanıtla (Reader Pod)

Pod geçicidir, ancak PVC kalıcıdır. `writer` Pod'unu silip aynı diski bağlayan `reader` Pod'u ile dosyayı okuyalım:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: reader
spec:
  restartPolicy: Never
  containers:
    - name: reader
      image: busybox:1.37
      command:
        - sh
        - -c
        - "cat /data/message.txt"
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: static-pvc
```

Writer pod'unu sil ve Reader'ı başlat:

```bash
kubectl -n storage-lab delete pod writer
kubectl apply -n storage-lab -f starter/reader.yaml
kubectl -n storage-lab wait --for=jsonpath='{.status.phase}'=Succeeded pod/reader --timeout=90s
kubectl -n storage-lab logs reader
```

Beklenen sonuç: Reader logunda Writer'ın yazdığı aynı tarih bilgisi okunur. Pod yok olsa da veri korunmuştur.

---

## 6. Dynamic PVC oluştur

Dynamic depolamada önceden bir PV oluşturulmaz. PVC içinde `storageClassName: local-path` belirtilerek diskin otomatik açılması istenir:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: dynamic-pvc
spec:
  storageClassName: local-path
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

Dynamic PVC'yi uygula:

```bash
kubectl apply -n storage-lab -f starter/dynamic-pvc.yaml
kubectl -n storage-lab get pvc dynamic-pvc
```

Beklenen sonuç: PVC ilk anda `Pending` kalabilir. Çünkü `local-path` depolama sınıfı `WaitForFirstConsumer` modundadır; yani diskin hangi node üzerinde açılacağını belirlemek için PVC'yi kullanan bir Pod'un gelmesini bekler.

---

## 7. Dynamic PVC'yi kullanan Pod'u başlat

Aşağıdaki Pod (`starter/dynamic-consumer.yaml`), `dynamic-pvc`'yi bağlayarak diskin otomatik üretilmesini (provisioning) tetikler:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: dynamic-consumer
spec:
  containers:
    - name: consumer
      image: busybox:1.37
      command:
        - sh
        - -c
        - "echo dynamic-volume-ready > /data/status.txt; sleep 3600"
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: dynamic-pvc
```

Pod'u çalıştır ve otomatik oluşan PV'yi gör:

```bash
kubectl apply -n storage-lab -f starter/dynamic-consumer.yaml
kubectl -n storage-lab get pods,pvc
kubectl get pv
```

Beklenen sonuç: Pod `Running` olur, `dynamic-pvc` anında `Bound` durumuna geçer ve Kubernetes tarafından otomatik olarak `pvc-...` adıyla yeni bir PV oluşturulduğu listelenir.

## Başarı kriterleri

- Static PV ile PVC'yi `Bound` durumuna getirdiniz.
- Pod silindikten sonra verinin PVC üzerinde kaldığını doğruladınız.
- Dynamic PVC için PV'nin otomatik oluşturulduğunu gördünüz.

## Temizlik

Önce namespace'i, ardından cluster kapsamlı static PV'yi silin:

```bash
kubectl delete namespace storage-lab
kubectl delete pv static-pv --ignore-not-found
```

`local-path` provisioner başka lablarda kullanılabileceği için kurulu bırakılır.
