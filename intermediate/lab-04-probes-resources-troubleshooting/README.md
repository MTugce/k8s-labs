# Health Check, Kaynak Yönetimi ve Troubleshooting

> **Seviye:** Orta
> **Tahmini süre:** 60–75 dakika
> **Lab Kapsamı:** Zorunlu

## Amaç

Bu labda sağlıklı bir uygulamaya startup, readiness ve liveness probe ekleyecek; CPU ve bellek kaynaklarını inceleyecek; bilerek oluşturulan dört farklı hatayı `kubectl` komutlarıyla teşhis edeceksiniz.

## Çalışma dizini

```bash
cd ~/k8s-labs/intermediate/lab-04-probes-resources-troubleshooting
```

## 1. Sağlıklı uygulamayı başlat

```bash
kubectl apply -f starter/healthy-app.yaml
kubectl rollout status deployment/health-web -n health-lab --timeout=120s
kubectl wait -n health-lab --for=condition=Ready pod/test-client --timeout=90s
kubectl get pods -n health-lab
```

Beklenen sonuç: İki `health-web` Pod'u ve `test-client` Pod'u `Running` ve `Ready` durumundadır.

Uygulamayı Service üzerinden test edin:

```bash
kubectl exec -n health-lab test-client -- curl -s http://health-web
kubectl exec -n health-lab test-client -- curl -s http://health-web/healthz
kubectl exec -n health-lab test-client -- curl -s http://health-web/ready
```

Beklenen yanıtlar sırasıyla `application-ok`, `healthy` ve `ready` olur.

## 2. Probe ve kaynak ayarlarını incele

Deployment'ın tanımladığı probe'ları görüntüleyin:

```bash
kubectl describe deployment health-web -n health-lab
```

Pod kaynak isteklerini ve limitlerini yazdırın:

```bash
kubectl get pod -n health-lab -l app=health-web \
  -o custom-columns='NAME:.metadata.name,CPU-REQUEST:.spec.containers[0].resources.requests.cpu,MEMORY-REQUEST:.spec.containers[0].resources.requests.memory,CPU-LIMIT:.spec.containers[0].resources.limits.cpu,MEMORY-LIMIT:.spec.containers[0].resources.limits.memory'
```

- **startupProbe:** Uygulamanın ilk açılışını bekler.
- **readinessProbe:** Pod'un trafik almaya hazır olup olmadığını belirler.
- **livenessProbe:** Çalışmayan container'ın yeniden başlatılmasını sağlar.
- **requests:** Scheduler'ın yer ayırırken kullandığı minimum kaynaktır.
- **limits:** Container'ın kullanabileceği üst sınırdır.

## 3. ImagePullBackOff hatasını teşhis et

Olmayan bir image etiketi kullanan Pod'u oluşturun:

```bash
kubectl apply -f starter/broken-image.yaml
kubectl get pod broken-image -n health-lab
```

Bir süre sonra Pod `ErrImagePull` veya `ImagePullBackOff` durumuna geçer. Nedeni bulun:

```bash
kubectl describe pod broken-image -n health-lab
kubectl get events -n health-lab --sort-by=.metadata.creationTimestamp
```

`Events` bölümünde image etiketinin bulunamadığını belirten mesaj görünür.

Kaynağı temizleyin:

```bash
kubectl delete pod broken-image -n health-lab
```

## 4. CrashLoopBackOff hatasını teşhis et

Başladıktan hemen sonra hata koduyla kapanan container'ı çalıştırın:

```bash
kubectl apply -f starter/broken-command.yaml
kubectl get pod broken-command -n health-lab
```

Mevcut ve bir önceki container loglarını okuyun:

```bash
kubectl logs broken-command -n health-lab
kubectl logs broken-command -n health-lab --previous
kubectl describe pod broken-command -n health-lab
```

Beklenen sonuç: Logda `uygulama-basliyor` görünür; container `exit 1` ile kapandığı için Kubernetes tekrar başlatır.

```bash
kubectl delete pod broken-command -n health-lab
```

## 5. Readiness başarısızlığını incele

Yanlış probe adresi kullanan Pod'u oluşturun:

```bash
kubectl apply -f starter/failed-readiness.yaml
kubectl get pod failed-readiness -n health-lab
```

Pod çalışmasına rağmen `READY` değeri `0/1` olur. Ayrıntıyı inceleyin:

```bash
kubectl describe pod failed-readiness -n health-lab
```

Beklenen olay: `/not-ready` adresi `404` döndürdüğü için `Readiness probe failed` mesajı görünür.

```bash
kubectl delete pod failed-readiness -n health-lab
```

## 6. Kaynak yetersizliğinde Pending durumunu incele

Cluster'dan gerçekçi olmayan miktarda CPU ve bellek isteyen Pod'u oluşturun:

```bash
kubectl apply -f starter/resource-pending.yaml
kubectl get pod resource-pending -n health-lab
```

Pod `Pending` durumunda kalır. Scheduler mesajını bulun:

```bash
kubectl describe pod resource-pending -n health-lab
```

Beklenen sonuç: `Insufficient cpu` veya `Insufficient memory` mesajı görünür.

```bash
kubectl delete pod resource-pending -n health-lab
```

## 7. Hazır Pod'ların Service endpoint'lerini doğrula

```bash
kubectl get endpointslice -n health-lab -l kubernetes.io/service-name=health-web
kubectl get pods -n health-lab -l app=health-web
```

Yalnızca readiness kontrolünü geçen Pod'lar Service trafiği alır.

## Başarı kriterleri

- Üç probe türünün görevini açıklayabiliyorsunuz.
- Requests ve limits değerlerini Pod üzerinden okuyabiliyorsunuz.
- `ImagePullBackOff`, `CrashLoopBackOff`, readiness hatası ve `Pending` durumlarının nedenlerini bulabiliyorsunuz.
- Teşhis için `get`, `describe`, `logs`, `logs --previous` ve Events kullanabiliyorsunuz.

## Opsiyonel İleri Seviye Görev

`failed-readiness.yaml` dosyasındaki probe yolunu `/` yaparak yeni bir yerel dosya oluşturun ve Pod'un `Ready` olduğunu kanıtlayın:

```bash
sed 's|path: /not-ready|path: /|' starter/failed-readiness.yaml | kubectl apply -f -
kubectl wait -n health-lab --for=condition=Ready pod/failed-readiness --timeout=60s
```

## Temizlik

```bash
kubectl delete namespace health-lab
```
