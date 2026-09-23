# * Paylaşımlı Depolama ve StatefulSet ile MySQL

## Amaç

NFS üzerinde `ReadWriteMany` (RWX) dinamik depolama ile StatefulSet'in sıralı kimlik ve kalıcı veri davranışını uygulamalı olarak öğrenmek.

## Kullanılan Kubernetes nesneleri

- **StatefulSet:** Sabit/sıralı Pod adı (`mysql-0`) ve her Pod için otomatik bağımsız kalıcı disk sağlar.
- **Headless Service (`clusterIP: None`):** StatefulSet Pod'larına tek tek doğrudan DNS adı verir.
- **StorageClass & RWX PVC:** Birden fazla Pod'un aynı anda yazabildiği NFS depolama alanıdır.

## Çalışma dizini

```bash
cd ~/k8s-labs/lab-06-nfs-storage-and-statefulset
```

---

## 1. NFS Sunucusunu Başlat

Aşağıdaki manifest (`starter/nfs-server.yaml`), laboratuvar ortamında paylaşımlı disk alanı sunacak hafif bir NFS sunucusu ve Service tanımlar:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: nfs-lab
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nfs-server
  namespace: nfs-lab
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nfs-server
  template:
    metadata:
      labels:
        app: nfs-server
    spec:
      containers:
        - name: nfs
          image: itsthenetwork/nfs-server-alpine:12
          securityContext:
            privileged: true
          env:
            - name: SHARED_DIRECTORY
              value: /nfsshare
          ports:
            - containerPort: 2049
          volumeMounts:
            - name: nfs-share
              mountPath: /nfsshare
      volumes:
        - name: nfs-share
          emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: nfs-server
  namespace: nfs-lab
spec:
  selector:
    app: nfs-server
  ports:
    - port: 2049
      targetPort: 2049
```

NFS sunucusunu kur ve hazır olmasını bekle:

```bash
kubectl apply -f starter/nfs-server.yaml
kubectl -n nfs-lab wait --for=condition=Ready pod -l app=nfs-server --timeout=180s
kubectl -n nfs-lab get pods,service
```

Beklenen sonuç: `nfs-server` Pod'u `Running` ve Service `ClusterIP` ile listelenir.

---

## 2. NFS Dinamik Depolama Sınıfını (StorageClass) Kur

NFS sunucusunun IP adresini alıp Helm provisioner'ı kurarak PVC'lerin otomatik disk açabilmesini sağlayacağız:

```bash
export NFS_SERVER="$(kubectl -n nfs-lab get service nfs-server -o jsonpath='{.spec.clusterIP}')"
echo "NFS Sunucu IP: $NFS_SERVER"
```

Provisioner'ı Helm ile kur ve `lab-nfs` StorageClass'ını oluştur:

```bash
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm repo update

helm upgrade --install nfs-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --version 4.0.18 --namespace nfs-lab \
  --set nfs.server="$NFS_SERVER" --set nfs.path=/ \
  --set storageClass.name=lab-nfs --wait
```

Depolama sınıfını doğrula:

```bash
kubectl get storageclass lab-nfs
```

Beklenen sonuç: `lab-nfs` StorageClass'ı listelenir.

---

## 3. Paylaşımlı Depolamayı (RWX) İki Pod ile Test Et

Aşağıdaki manifest (`starter/rwx-writers.yaml`), `ReadWriteMany` erişim moduna sahip tek bir PVC (`shared-rwx`) oluşturur ve bu diski aynı anda iki farklı Pod'a (`writer-a` ve `writer-b`) bağlar:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: shared-rwx
  namespace: nfs-lab
spec:
  storageClassName: lab-nfs
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: writer-a
  namespace: nfs-lab
spec:
  containers:
    - name: writer
      image: busybox:1.37
      command:
        - sh
        - -c
        - "echo writer-a >> /data/shared.txt; sleep 3600"
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: shared-rwx
---
apiVersion: v1
kind: Pod
metadata:
  name: writer-b
  namespace: nfs-lab
spec:
  containers:
    - name: writer
      image: busybox:1.37
      command:
        - sh
        - -c
        - "echo writer-b >> /data/shared.txt; cat /data/shared.txt; sleep 3600"
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: shared-rwx
```

Manifesti uygula ve iki Pod'un ortak dosyaya yazdığını kanıtla:

```bash
kubectl apply -f starter/rwx-writers.yaml
kubectl -n nfs-lab wait --for=condition=Ready pod/writer-a pod/writer-b --timeout=180s
kubectl -n nfs-lab exec writer-b -- cat /data/shared.txt
```

Beklenen sonuç: Çıktıda hem `writer-a` hem de `writer-b` satırı görünür. İki Pod aynı diske eşzamanlı olarak yazabilmiştir.

---

## 4. MySQL Parolasını Secret Olarak Oluştur

Veritabanı için ayrı bir namespace açıp parolasını Secret olarak kaydedelim:

```bash
kubectl create namespace stateful-lab --dry-run=client -o yaml | kubectl apply -f -
export MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-MyRootSecretPass123}"

kubectl -n stateful-lab create secret generic mysql-secret \
  --from-literal=MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD"

kubectl -n stateful-lab get secret mysql-secret
```

---

## 5. MySQL StatefulSet'i İncele ve Başlat

StatefulSet nesnesi, Deployment'tan farklı olarak Pod'lara rastgele hash değil sıralı ve sabit isim (`mysql-0`) verir. `volumeClaimTemplates` alanı ise her replica için otomatik olarak ayrı ve kalıcı bir PVC üretir:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mysql-headless
  namespace: stateful-lab
spec:
  clusterIP: None                   # Headless Service (IP atamadan pod'a özel DNS)
  selector:
    app: mysql
  ports:
    - port: 3306
      name: mysql
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
  namespace: stateful-lab
spec:
  serviceName: mysql-headless        # Headless Service eşlemesi
  replicas: 1
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
        - name: mysql
          image: mysql:8.4
          env:
            - name: MYSQL_ROOT_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: mysql-secret
                  key: MYSQL_ROOT_PASSWORD
          volumeMounts:
            - name: mysql-data
              mountPath: /var/lib/mysql
  volumeClaimTemplates:              # Her replica için otomatik PVC açar
    - metadata:
        name: mysql-data
      spec:
        storageClassName: lab-nfs
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 1Gi
```

StatefulSet manifestini uygula ve Pod'un başlamasını bekle:

```bash
kubectl apply -f starter/mysql-statefulset.yaml
kubectl -n stateful-lab rollout status statefulset/mysql --timeout=180s
kubectl -n stateful-lab get statefulset,pods,pvc,service
```

Beklenen sonuç:
- Pod adı `mysql-0` olur.
- PVC adı otomatik olarak `mysql-data-mysql-0` olarak açılır ve `lab-nfs` StorageClass ile `Bound` duruma geçer.
- `mysql-headless` servisi Pod'a küme içinde `mysql-0.mysql-headless.stateful-lab.svc.cluster.local` DNS adresi sağlar.
