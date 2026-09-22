# * Veriyi Kaybetme: PV, PVC, Static ve Dynamic Storage

## Amaç

Static ve dynamic PV/PVC akışlarını aynı cluster üzerinde karşılaştırmak.

## Kullanılan Kubernetes nesneleri

- **PV:** Cluster'ın sunduğu disk kaynağıdır.
- **PVC:** Uygulamanın talep ettiği disk alanıdır.
- **StorageClass:** Dynamic PV'yi oluşturacak provisioner'ı seçer.
- **Pod:** PVC'ye bağlanıp veriyi okur veya yazar.

## Çalışma dizini

```bash
cd ~/k8s-labs/lab-05-static-and-dynamic-storage
```

## * Doğrulanan senaryo

Static PV/PVC `Bound` oldu. Writer Pod'unun yazdığı veri, Pod silindikten sonra
Reader tarafından okundu. Dynamic PVC ise otomatik olarak yeni bir PV oluşturdu.

## Kavramlar

- **PV:** Cluster'ın sunduğu depolama alanıdır.
- **PVC:** Uygulamanın istediği depolama alanıdır.
- **StorageClass:** PVC geldiğinde hangi provisioner'ın PV yaratacağını tanımlar.
- **Static storage:** PV önce yönetici tarafından oluşturulur.
- **Dynamic storage:** PVC isteğiyle PV otomatik oluşturulur.

## 1. Dynamic storage provisioner'ını kur

Static PV'yi sen oluşturacaksın. Dynamic PVC ise PV'yi otomatik oluşturan bir provisioner'a ihtiyaç duyar. Bu labda `local-path` provisioner kullanılır.

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.36/deploy/local-path-storage.yaml
kubectl wait -n local-path-storage --for=condition=Available deployment/local-path-provisioner --timeout=180s
kubectl get storageclass local-path
```

Beklenen sonuç: `local-path` StorageClass'ı görünür.

## 2. Static storage namespace'ini oluştur

```bash
kubectl create namespace storage-lab
kubectl get namespace storage-lab
```

Beklenen sonuç: `storage-lab` `Active` görünür.

## 3. Static PV ve PVC'yi bağla

Platform Hazırlığı sırasında `/opt/k8s-labs/static-pv` host dizini Kind node'larına bağlanmıştı. Bu manifestteki PV, Kind içindeki `/mnt/k8s-labs/static-pv` yolunu kullanır. PVC ise özellikle bu PV'yi ister.

```bash
kubectl apply -n storage-lab -f ~/k8s-labs/lab-05-static-and-dynamic-storage/starter/static-pv-pvc.yaml
kubectl get pv static-pv
kubectl -n storage-lab get pvc static-pvc
```

Beklenen sonuç: PV ve PVC `Bound` olur. `storageClassName: ""` alanı, dynamic provisioner kullanılmadığını gösterir.

## 4. PVC'ye veri yaz

Writer Pod'u PVC'yi `/data` yoluna bağlar ve içine tarih bilgisi yazar.

```bash
kubectl apply -n storage-lab -f ~/k8s-labs/lab-05-static-and-dynamic-storage/starter/writer.yaml
kubectl -n storage-lab wait --for=jsonpath='{.status.phase}'=Succeeded pod/writer --timeout=90s
kubectl -n storage-lab logs writer
```

Beklenen sonuç: logda tarih bilgisi görünür.

## 5. Writer Pod silinse de verinin kaldığını göster

Pod geçicidir; PVC kalıcıdır. Writer Pod'u sil ve farklı Reader Pod'u ile aynı dosyayı oku.

```bash
kubectl -n storage-lab delete pod writer
kubectl apply -n storage-lab -f ~/k8s-labs/lab-05-static-and-dynamic-storage/starter/reader.yaml
kubectl -n storage-lab wait --for=jsonpath='{.status.phase}'=Succeeded pod/reader --timeout=90s
kubectl -n storage-lab logs reader
```

Beklenen sonuç: Reader logunda Writer'ın yazdığı aynı tarih görünür.

## 6. Dynamic PVC oluştur

Bu PVC'de `volumeName` yoktur. `storageClassName: local-path`, local-path provisioner'a yeni PV oluşturmasını söyler.

```bash
kubectl get storageclass local-path
kubectl apply -n storage-lab -f ~/k8s-labs/lab-05-static-and-dynamic-storage/starter/dynamic-pvc.yaml
kubectl -n storage-lab get pvc dynamic-pvc
```

Beklenen sonuç: PVC ilk anda `Pending` kalabilir. Bu StorageClass `WaitForFirstConsumer` kullanır; bir Pod PVC'yi istemeden hangi node üzerinde volume açılacağı belli değildir.

## 7. Dynamic PVC'yi kullanan Pod'u başlat

```bash
kubectl apply -n storage-lab -f ~/k8s-labs/lab-05-static-and-dynamic-storage/starter/dynamic-consumer.yaml
kubectl -n storage-lab get pods,pvc
kubectl get pv
```

Beklenen sonuç: `dynamic-consumer` çalışır, `dynamic-pvc` `Bound` olur ve `pvc-...` adlı yeni bir PV listelenir. Static ve dynamic storage farkını böylece gerçek kaynaklarda görmüş oldun.
