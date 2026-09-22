# Veriyi Kaybetme: PV, PVC, Static ve Dynamic Storage

| Seviye | Tahmini Süre | Profil / Araçlar | Açık Portlar |
| --- | --- | --- | --- |
| Orta | 50 dk | kubectl | — |

## Amaç

- HostPath ile static PV/PVC bağlanmasını görmek.
- `local-path` StorageClass üzerinden dynamic PVC oluşumunu izlemek.

## Adım Adım Uygulama Rehberi

```bash
kubectl create namespace storage-lab
kubectl apply -n storage-lab -f labs/lab-06-static-and-dynamic-storage/starter/static-pv-pvc.yaml
kubectl apply -n storage-lab -f labs/lab-06-static-and-dynamic-storage/starter/writer.yaml
kubectl logs -n storage-lab writer
kubectl delete -n storage-lab pod/writer
kubectl apply -n storage-lab -f labs/lab-06-static-and-dynamic-storage/starter/reader.yaml
kubectl logs -n storage-lab reader
```

Dynamic storage için:

```bash
kubectl get storageclass
kubectl apply -n storage-lab -f labs/lab-06-static-and-dynamic-storage/starter/dynamic-pvc.yaml
kubectl apply -n storage-lab -f labs/lab-06-static-and-dynamic-storage/starter/dynamic-consumer.yaml
kubectl get pv,pvc -n storage-lab
```

## Doğal Doğrulama ve Beklenen Sonuç

`reader` eski mesajı görmelidir. Static PVC `static-pv`ye, dynamic PVC ise `local-path` tarafından üretilen ayrı PV'ye bağlanmalıdır.
