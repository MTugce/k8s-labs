# Her Node'da Ajan Çalıştır ve Uygulamanı Otomatik Ölçekle

Bu labı şu klasörde uygulayacaksın:

```bash
cd ~/k8s-labs/lab-07-daemonset-and-hpa-scaling
```

## Bu labda ne yapacaksın?

DaemonSet ile her node'a bir ajan Pod'u koyacak, sonra `devops-app` için HPA oluşturacaksın. Yük üreterek replica sayısının arttığını, yük kesilince tekrar azaldığını izleyeceksin.

## Başlamadan önce Lab 2 kontrolü

HPA, Lab 2'de oluşturduğun `devops-app` Deployment'ını ölçekler. Önce kaynağın bulunduğunu doğrula.

```bash
kubectl -n private-app get deployment devops-app
```

Beklenen sonuç: `devops-app` görünür ve `AVAILABLE` değeri sıfırdan büyüktür.

`NotFound` veya `No resources found` görürsen bu labda ilerleme; önce Lab 2'nin final Deployment adımını tamamla.

## 1. Metrics Server kur

HPA, CPU bilgisini Metrics Server'dan alır. Kind node'larının sertifika ayarı nedeniyle bu labda `--kubelet-insecure-tls` parametresi eklenir.

Önce Metrics Server kaynaklarını cluster'a ekle.

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.7.2/components.yaml
```

Kind node sertifikasını kabul etmesi için Metrics Server'a ek parametre ver. Bu labın `starter` klasöründeki dosya, eklenecek tek parametreyi içerir.

```bash
kubectl -n kube-system patch deployment metrics-server --type=json \
  --patch-file starter/metrics-server-kind-patch.json
```

Deployment hazır olana kadar bekle.

```bash
kubectl wait -n kube-system --for=condition=Available deployment/metrics-server --timeout=180s
```

Beklenen sonuç: `metrics-server` Deployment'ı kullanılabilir olur.

## 2. Metrics Server'ın veri verdiğini doğrula

HPA, CPU yüzdesini Metrics Server'dan alır. Önce veri geldiğini kontrol et.

Önce node metriklerini gör.

```bash
kubectl top nodes
```

Sonra uygulama Pod'larının metriklerini gör.

```bash
kubectl top pods -n private-app
```

Beklenen sonuç: her node ve uygulama Pod'u için CPU/memory değerleri görünür. Değerler görünmüyorsa birkaç dakika bekle; sorun sürerse platform hazırlığını kontrol et.

## 3. DaemonSet uygula

Deployment belirli sayıda Pod çalıştırır. DaemonSet ise her uygun node'da bir Pod çalıştırır. Bu labdaki toleration sayesinde control-plane de dahil edilir.

```bash
kubectl apply -f starter/daemonset.yaml
```

DaemonSet ve oluşturduğu Pod'ları kontrol et.

```bash
kubectl -n private-app get daemonset node-label-agent
kubectl -n private-app get pods -l app=node-label-agent -o wide
```

Beklenen sonuç: üç node olduğu için üç ajan Pod'u görünür. `NODE` sütununda her node için bir Pod vardır.

## 4. HPA oluştur

HPA, Deployment'ın CPU kullanımını istek değerinin yüzdesiyle karşılaştırır. Bu uygulamada CPU request tanımlı olduğu için HPA hedefi hesaplanabilir.

```bash
kubectl apply -n private-app -f starter/hpa.yaml
```

Oluşan HPA'yı incele.

```bash
kubectl -n private-app get hpa devops-app
```

Beklenen sonuç: minimum replica `1`, maksimum replica `6`, CPU hedefi `%50` görünür. İlk değerin `unknown` olması kısa süreli normaldir.

## 5. Yük üret

`/work?ms=500` endpoint'i isteği işlerken CPU kullanır. `starter/load-generator.yaml`, bu endpoint'e sürekli istek atan geçici Pod'u tanımlar. Önce dosyayı açıp komutu incele.

```bash
cat starter/load-generator.yaml
```

Yük üreticisini başlat.

```bash
kubectl -n private-app apply -f starter/load-generator.yaml
kubectl -n private-app get pod load-generator
```

Pod `Running` kaldığı sürece yük üretir.

## 6. Başka terminalde scale-out'u izle

```bash
kubectl -n private-app get hpa,pods -w
```

Beklenen sonuç: CPU hedefin üstüne çıktığında HPA replica sayısını artırır; yeni `devops-app-...` Pod'ları oluşur. İzlemeyi `Ctrl+C` ile bitir.

## 7. Yükü durdur ve scale-in'i izle

Yük üreticisini sil. Sonra tekrar izle.

```bash
kubectl -n private-app delete pod load-generator
```

```bash
kubectl -n private-app get hpa,pods -w
```

Beklenen sonuç: HPA, Kubernetes'in soğuma süresi sonunda Pod sayısını minimum replica değerine indirir. Bu hemen olmaz; birkaç dakika beklemek normaldir.

Bu labda DaemonSet'in node bazlı, HPA'nın ise metrik bazlı çalıştığını gerçek yük altında gördün.
