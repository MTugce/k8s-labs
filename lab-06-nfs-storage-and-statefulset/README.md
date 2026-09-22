# * Paylaşımlı Depolama ve StatefulSet ile MySQL

## Amaç

NFS üzerinde RWX dynamic storage ile StatefulSet'in kalıcı veri davranışını görmek.

## Kullanılan Kubernetes nesneleri

- **StatefulSet:** Sabit Pod adı ve her Pod için ayrı kalıcı disk sağlar.
- **Headless Service:** StatefulSet Pod'larına tek tek DNS adı verir.
- **StorageClass/PVC:** NFS üzerinde dynamic ve RWX disk alanı oluşturur.

## Çalışma dizini

```bash
cd ~/k8s-labs/lab-06-nfs-storage-and-statefulset
```

## * Doğrulanan senaryo

NFS provisioner ile `lab-nfs` StorageClass oluştu. İki writer Pod'u aynı RWX
PVC'ye yazdı; MySQL `mysql-0` Pod'u ve kendi PVC'si `Bound` duruma geldi.

## 1. NFS server'ı başlat

NFS server, bu eğitimde paylaşımlı dosya alanı sağlar. Production NFS sunucusu değildir; yalnızca lab içindir.

```bash
kubectl apply -f ~/k8s-labs/lab-06-nfs-storage-and-statefulset/starter/nfs-server.yaml
kubectl -n nfs-lab wait --for=condition=Ready pod -l app=nfs-server --timeout=180s
kubectl -n nfs-lab get pods,service
```

Beklenen sonuç: `nfs-server` Pod'u `Running`, aynı isimli Service ise `ClusterIP` ile görünür.

## 2. NFS provisioner'ı kur

Provisioner, her PVC için NFS altında ayrı bir dizin açar. NFS Service'ine cluster içindeki sabit DNS adıyla erişebilir.

```bash
export NFS_SERVER="$(kubectl -n nfs-lab get service nfs-server -o jsonpath='{.spec.clusterIP}')"
echo "$NFS_SERVER"
```

Beklenen sonuç: NFS Service'in ClusterIP adresi görünür. Provisioner, NFS
volume'unu node üzerinden mount ettiği için burada Service DNS adı değil,
ClusterIP kullanılır; node'lar Kubernetes Service DNS alanını çözemez.

Şimdi Helm ile provisioner'ı ve `lab-nfs` StorageClass'ını kur.

```bash
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm upgrade --install nfs-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --version 4.0.18 --namespace nfs-lab \
  --set nfs.server="$NFS_SERVER" --set nfs.path=/ \
  --set storageClass.name=lab-nfs --wait
kubectl get storageclass lab-nfs
```

Beklenen sonuç: `lab-nfs` StorageClass'ı listelenir.

## 3. RWX PVC'yi iki Pod ile kullan

`ReadWriteMany`, birden fazla Pod'un aynı volume'u aynı anda bağlayabilmesini sağlar.

```bash
kubectl apply -f ~/k8s-labs/lab-06-nfs-storage-and-statefulset/starter/rwx-writers.yaml
kubectl -n nfs-lab wait --for=condition=Ready pod/writer-a pod/writer-b --timeout=180s
kubectl -n nfs-lab get pvc,pods
kubectl -n nfs-lab exec writer-b -- cat /data/shared.txt
```

Beklenen sonuç: PVC `Bound` olur. Dosyada hem `writer-a` hem `writer-b` satırı görünür. Bu, iki Pod'un aynı NFS alanını kullandığını kanıtlar.

## 4. MySQL Secret'ını terminalden oluştur

Parola manifestte yer almaz. Terminal gizli giriş ister; kubectl bunu Secret olarak cluster'a yazar.

```bash
kubectl create namespace stateful-lab
read -rsp "MySQL root parolası: " MYSQL_ROOT_PASSWORD; echo
kubectl -n stateful-lab create secret generic mysql-secret \
  --from-literal=MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD"
kubectl -n stateful-lab get secret mysql-secret
```

Beklenen sonuç: yalnızca Secret adı ve türü görünür; parola görüntülenmez.

## 5. MySQL StatefulSet'i uygula

StatefulSet, Pod'a sıralı ve sabit isim verir. `volumeClaimTemplates`, her replica için ayrı PVC oluşturur.

```bash
kubectl apply -f ~/k8s-labs/lab-06-nfs-storage-and-statefulset/starter/mysql-statefulset.yaml
kubectl -n stateful-lab get statefulset,pods,pvc,service
kubectl -n stateful-lab wait --for=condition=Ready pod/mysql-0 --timeout=180s
```

Beklenen sonuç:

- Pod adı `mysql-0` olur.
- Headless Service adı `mysql-headless` olur.
- PVC adı `mysql-data-mysql-0` olur.
- PVC, `lab-nfs` StorageClass ile `Bound` görünür.

Bu labda shared NFS storage ile StatefulSet'in Pod kimliği ve kalıcı disk modelini birlikte uyguladın.
