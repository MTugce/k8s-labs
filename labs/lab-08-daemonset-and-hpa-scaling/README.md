# Her Node'da Ajan Çalıştır ve Uygulamanı Otomatik Ölçekle

| Seviye | Tahmini Süre | Profil / Araçlar | Açık Portlar |
| --- | --- | --- | --- |
| Orta | 55 dk | kubectl, Metrics Server | `30087` |

## Bu labda ne yapacaksın?

DaemonSet ile her node'a bir ajan Pod'u koyacak, sonra `devops-app` için HPA oluşturacaksın. Yük üreterek replica sayısının arttığını, yük kesilince tekrar azaldığını izleyeceksin.

## 1. Metrics Server'ın veri verdiğini doğrula

HPA, CPU yüzdesini Metrics Server'dan alır. Önce veri geldiğini kontrol et.

```bash
kubectl top nodes
kubectl top pods -n private-app
```

Beklenen sonuç: her node ve uygulama Pod'u için CPU/memory değerleri görünür. Değerler görünmüyorsa birkaç dakika bekle; sorun sürerse platform hazırlığını kontrol et.

## 2. DaemonSet uygula

Deployment belirli sayıda Pod çalıştırır. DaemonSet ise her uygun node'da bir Pod çalıştırır. Bu labdaki toleration sayesinde control-plane de dahil edilir.

```bash
kubectl apply -f labs/lab-08-daemonset-and-hpa-scaling/starter/daemonset.yaml
kubectl -n private-app get daemonset node-label-agent
kubectl -n private-app get pods -l app=node-label-agent -o wide
```

Beklenen sonuç: üç node olduğu için üç ajan Pod'u görünür. `NODE` sütununda her node için bir Pod vardır.

## 3. HPA oluştur

HPA, Deployment'ın CPU kullanımını istek değerinin yüzdesiyle karşılaştırır. Bu uygulamada CPU request tanımlı olduğu için HPA hedefi hesaplanabilir.

```bash
kubectl apply -n private-app -f labs/lab-08-daemonset-and-hpa-scaling/starter/hpa.yaml
kubectl -n private-app get hpa devops-app
```

Beklenen sonuç: minimum replica `1`, maksimum replica `6`, CPU hedefi `%50` görünür. İlk değerin `unknown` olması kısa süreli normaldir.

## 4. Yük üret

`/work?ms=500` endpoint'i isteği işlerken CPU kullanır. Aşağıdaki geçici Pod, bu endpoint'e sürekli istek gönderir.

```bash
kubectl -n private-app run load-generator --rm -it --restart=Never \
  --image=curlimages/curl:8.12.1 -- \
  sh -c 'while true; do curl -s http://devops-app/work?ms=500 >/dev/null; done'
```

Bu terminal açık kalır ve yük üretir.

## 5. Başka terminalde scale-out'u izle

```bash
kubectl -n private-app get hpa,pods -w
```

Beklenen sonuç: CPU hedefin üstüne çıktığında HPA replica sayısını artırır; yeni `devops-app-...` Pod'ları oluşur. İzlemeyi `Ctrl+C` ile bitir.

## 6. Yükü durdur ve scale-in'i izle

İlk terminalde `Ctrl+C` ile load generator'ı durdur. Sonra tekrar izle.

```bash
kubectl -n private-app get hpa,pods -w
```

Beklenen sonuç: HPA, Kubernetes'in soğuma süresi sonunda Pod sayısını minimum replica değerine indirir. Bu hemen olmaz; birkaç dakika beklemek normaldir.

Bu labda DaemonSet'in node bazlı, HPA'nın ise metrik bazlı çalıştığını gerçek yük altında gördün.
