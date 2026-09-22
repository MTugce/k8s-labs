# Veriyi Kaybetme: PV, PVC, Static ve Dynamic Storage

| Seviye | Tahmini Süre | Profil / Araçlar | Açık Portlar |
| --- | --- | --- | --- |
| Orta | 55 dk | kubectl | — |

## Bu labda ne yapacaksın?

Önce önceden hazırlanmış bir HostPath alanına elle bağlanan static PV/PVC oluşturacaksın. Sonra `local-path` StorageClass kullanarak yalnızca PVC yazarak dynamic PV oluşturacaksın.

## Kavramlar

- **PV:** Cluster'ın sunduğu depolama alanıdır.
- **PVC:** Uygulamanın istediği depolama alanıdır.
- **StorageClass:** PVC geldiğinde hangi provisioner'ın PV yaratacağını tanımlar.
- **Static storage:** PV önce yönetici tarafından oluşturulur.
- **Dynamic storage:** PVC isteğiyle PV otomatik oluşturulur.

## 1. Static storage namespace'ini oluştur

```bash
kubectl create namespace storage-lab
kubectl get namespace storage-lab
```

Beklenen sonuç: `storage-lab` `Active` görünür.

## 2. Static PV ve PVC'yi bağla

Platform Hazırlığı sırasında `/opt/k8s-labs/static-pv` host dizini Kind node'larına bağlanmıştı. Bu manifestteki PV, Kind içindeki `/mnt/k8s-labs/static-pv` yolunu kullanır. PVC ise özellikle bu PV'yi ister.

```bash
kubectl apply -n storage-lab -f labs/lab-06-static-and-dynamic-storage/starter/static-pv-pvc.yaml
kubectl get pv static-pv
kubectl -n storage-lab get pvc static-pvc
```

Beklenen sonuç: PV ve PVC `Bound` olur. `storageClassName: ""` alanı, dynamic provisioner kullanılmadığını gösterir.

## 3. PVC'ye veri yaz

Writer Pod'u PVC'yi `/data` yoluna bağlar ve içine tarih bilgisi yazar.

```bash
kubectl apply -n storage-lab -f labs/lab-06-static-and-dynamic-storage/starter/writer.yaml
kubectl -n storage-lab wait --for=jsonpath='{.status.phase}'=Succeeded pod/writer --timeout=90s
kubectl -n storage-lab logs writer
```

Beklenen sonuç: logda tarih bilgisi görünür.

## 4. Writer Pod silinse de verinin kaldığını göster

Pod geçicidir; PVC kalıcıdır. Writer Pod'u sil ve farklı Reader Pod'u ile aynı dosyayı oku.

```bash
kubectl -n storage-lab delete pod writer
kubectl apply -n storage-lab -f labs/lab-06-static-and-dynamic-storage/starter/reader.yaml
kubectl -n storage-lab wait --for=jsonpath='{.status.phase}'=Succeeded pod/reader --timeout=90s
kubectl -n storage-lab logs reader
```

Beklenen sonuç: Reader logunda Writer'ın yazdığı aynı tarih görünür.

## 5. Dynamic PVC oluştur

Bu PVC'de `volumeName` yoktur. `storageClassName: local-path`, local-path provisioner'a yeni PV oluşturmasını söyler.

```bash
kubectl get storageclass local-path
kubectl apply -n storage-lab -f labs/lab-06-static-and-dynamic-storage/starter/dynamic-pvc.yaml
kubectl -n storage-lab get pvc dynamic-pvc
```

Beklenen sonuç: PVC ilk anda `Pending` kalabilir. Bu StorageClass `WaitForFirstConsumer` kullanır; bir Pod PVC'yi istemeden hangi node üzerinde volume açılacağı belli değildir.

## 6. Dynamic PVC'yi kullanan Pod'u başlat

```bash
kubectl apply -n storage-lab -f labs/lab-06-static-and-dynamic-storage/starter/dynamic-consumer.yaml
kubectl -n storage-lab get pods,pvc
kubectl get pv
```

Beklenen sonuç: `dynamic-consumer` çalışır, `dynamic-pvc` `Bound` olur ve `pvc-...` adlı yeni bir PV listelenir. Static ve dynamic storage farkını böylece gerçek kaynaklarda görmüş oldun.
