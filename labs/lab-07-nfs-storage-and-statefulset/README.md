# Paylaşımlı Depolama ve StatefulSet ile MySQL

| Seviye | Tahmini Süre | Profil / Araçlar | Açık Portlar |
| --- | --- | --- | --- |
| Orta | 60 dk | kubectl, Helm | — |

## Amaç

- NFS Subdir provisioner ile RWX dynamic PVC oluşturmak.
- Çoklu Pod'un aynı NFS alanını kullandığını görmek.
- Headless Service ve `volumeClaimTemplates` ile MySQL StatefulSet çalıştırmak.

## Adım Adım Uygulama Rehberi

```bash
kubectl apply -f labs/lab-07-nfs-storage-and-statefulset/starter/nfs-server.yaml
kubectl wait -n nfs-lab --for=condition=Ready pod -l app=nfs-server --timeout=180s
NFS_IP=$(kubectl -n nfs-lab get svc nfs-server -o jsonpath='{.spec.clusterIP}')
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm upgrade --install nfs-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --version 4.0.18 -n nfs-lab --set nfs.server="$NFS_IP" --set nfs.path=/ --set storageClass.name=lab-nfs --wait
kubectl apply -f labs/lab-07-nfs-storage-and-statefulset/starter/rwx-writers.yaml
kubectl -n nfs-lab exec writer-b -- cat /data/shared.txt
kubectl create namespace stateful-lab
read -rsp "MySQL root parolası: " MYSQL_ROOT_PASSWORD; echo
kubectl -n stateful-lab create secret generic mysql-secret --from-literal=MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD"
kubectl apply -f labs/lab-07-nfs-storage-and-statefulset/starter/mysql-statefulset.yaml
kubectl -n stateful-lab get pod,pvc,svc
```

## Doğal Doğrulama ve Beklenen Sonuç

`writer-a` ve `writer-b` aynı PVC'ye satır ekler. MySQL pod adı `mysql-0`, Service adı `mysql-headless` ve PVC adı `mysql-data-mysql-0` olmalıdır.
