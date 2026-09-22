# * Sürümü Güvenle Yayınla: Recreate, Rolling, Blue-Green ve Canary

Bu labı şu klasörde uygulayacaksın:

```bash
cd ~/k8s-labs/lab-08-deployment-strategies
```

## Bu labda ne yapacaksın?

`devops-app:1.0` ve `devops-app:2.0` sürümlerini kullanarak dört yayın yaklaşımını karşılaştıracaksın. Her yaklaşımda hangi Pod'un trafik aldığını ve gerektiğinde rollback işlemini göreceksin.

## * Doğrulanan senaryo

Private Docker Hub image'leri ile Recreate, RollingUpdate ve rollback,
Blue-Green Service geçişi ve Gateway API üzerinden Canary ağırlıklı yönlendirme
çalıştırıldı. `1.0` ve `2.0` sürümleri Pod'lardan yanıt verdi.

## Başlamadan önce Lab 2 ve Lab 4 kontrolü

Bu labın ilk üç stratejisi Docker Hub'daki Lab 2 image'ini kullanır. Canary adımı ise Lab 4'te oluşturulan Gateway'i kullanır.

```bash
kubectl -n private-app get gateway devops-app-gateway
```

Beklenen sonuç: `devops-app-gateway` görünür.

Gateway bulunamazsa veya Lab 2'de `devops-app:1.0` image'ini Docker Hub'a göndermediysen bu labda ilerleme. Önce ilgili labı tamamla.

## 1. İkinci image sürümünü üret

İlk private image labında `1.0` image'ini gönderdin. Aynı uygulamayı `APP_VERSION=2.0` build argümanıyla yeniden üret.

Önce Docker Hub kullanıcı adını, iki image sürümünün adını ve kendi DNS adını değişkenlere yaz.

```bash
export DOCKERHUB_USER="KENDI_DOCKERHUB_KULLANICI_ADIN"
export IMAGE_V1="docker.io/${DOCKERHUB_USER}/devops-app:1.0"
export IMAGE_V2="docker.io/${DOCKERHUB_USER}/devops-app:2.0"
export APP_HOST="student01-app1.devopsatolyesi.com"
```

İkinci image'i üret ve Docker Hub'a gönder.

```bash
docker build --build-arg APP_VERSION=2.0 -t "$IMAGE_V2" ~/k8s-labs/app/devops-app
docker push "$IMAGE_V2"
```

Beklenen sonuç: Docker Hub'daki aynı `devops-app` repository'sinde iki ayrı tag bulunur: `1.0` ve `2.0`.

## 2. Recreate stratejisini uygula

Recreate, eski Pod'ları tamamen kapatır; yenileri ondan sonra açılır. Kısa kesinti riski vardır.

Starter manifestinin yerel bir kopyasını oluştur ve aç.

```bash
cp starter/recreate.yaml recreate.local.yaml
nano recreate.local.yaml
```

Dosyadaki `__IMAGE_V1__` değerini `$IMAGE_V1` değeriyle değiştir, kaydet ve çık. Ardından ilk sürümü uygula.

```bash
kubectl apply -f recreate.local.yaml
kubectl -n private-app rollout status deployment/devops-app-recreate
```

Şimdi Deployment image'ini ikinci sürüme değiştir.

```bash
kubectl -n private-app set image deployment/devops-app-recreate app="$IMAGE_V2"
```

Pod değişimini canlı izle. `Ctrl+C` ile izlemeyi bitir.

```bash
kubectl -n private-app get pods -l app=devops-app-recreate -w
```

Beklenen sonuç: eski Pod'lar sonlanır, sonra yeni Pod'lar oluşur. İzlemeyi `Ctrl+C` ile bitir.

## 3. RollingUpdate ve rollback uygula

RollingUpdate, yeni Pod'ları eski Pod'lar tamamen kapanmadan başlatır. Bu manifestte `maxUnavailable: 0` olduğu için hazır Pod sayısı düşmez.

Starter manifestini yerel kopyaya al ve `__IMAGE_V1__` değerini `$IMAGE_V1` ile değiştir.

```bash
cp starter/rolling.yaml rolling.local.yaml
nano rolling.local.yaml
```

İlk sürümü uygula ve hazır olmasını bekle.

```bash
kubectl apply -f rolling.local.yaml
kubectl -n private-app rollout status deployment/devops-app-rolling
```

Image'i ikinci sürüme al, rollout'u izle ve rollback uygula.

```bash
kubectl -n private-app set image deployment/devops-app-rolling app="$IMAGE_V2"
kubectl -n private-app rollout status deployment/devops-app-rolling
kubectl -n private-app rollout undo deployment/devops-app-rolling
```

Beklenen sonuç: image değişiminde Pod'lar sırayla yenilenir. Son komut Deployment'ı önceki `1.0` revision'ına döndürür.

## 4. Blue-Green geçişi yap

Blue ve green iki ayrı Deployment'tır. Service selector'ı hangi rengi seçerse trafik o renge gider.

Starter manifestini yerel kopyaya al. `__IMAGE_V1__` yerine `$IMAGE_V1`, `__IMAGE_V2__` yerine `$IMAGE_V2` yaz ve kaydet.

```bash
cp starter/blue-green.yaml blue-green.local.yaml
nano blue-green.local.yaml
```

Blue ve green kaynaklarını uygula, sonra iki sürümün Pod'larını gör.

```bash
kubectl apply -f blue-green.local.yaml
kubectl -n private-app get pods -l app=strategy-app --show-labels
```

Service'in blue sürümüne gittiğini geçici bir test Pod'uyla doğrula.

```bash
kubectl -n private-app run strategy-check \
  --image=curlimages/curl:8.12.1 \
  --restart=Never \
  -- sleep 3600
kubectl -n private-app wait --for=condition=Ready pod/strategy-check --timeout=90s
kubectl -n private-app exec strategy-check -- curl -s http://strategy-app/healthz
```

Beklenen sonuç: ilk istek `version: 1.0` döndürür; Service başlangıçta blue Pod'larını seçer.

Service selector'ını green'e çevir.

```bash
kubectl -n private-app patch service strategy-app \
  -p '{"spec":{"selector":{"app":"strategy-app","version":"green"}}}'
```

Aynı test Pod'undan tekrar istek gönder.

```bash
kubectl -n private-app exec strategy-check -- curl -s http://strategy-app/healthz
kubectl -n private-app delete pod strategy-check
```

Beklenen sonuç: ikinci istek `version: 2.0` döndürür. Pod yeniden yaratmadan trafik yönü değişmiştir.

## 5. Gateway API ile Canary dağıtımı yap

Canary'de iki Service aynı HTTPRoute içinde ağırlık alır. Önce Gateway API labındaki `devops-app-gateway` kaynaklarının çalıştığını doğrula.

Önce Gateway'in hazır olduğunu doğrula ve önceki uygulama route'unu sil.

```bash
kubectl -n private-app get gateway devops-app-gateway
kubectl -n private-app delete httproute devops-app-route --ignore-not-found
```

Canary manifestini yerel kopyaya al. `__IMAGE_V1__`, `__IMAGE_V2__` ve `__APP_HOST__` değerlerini sırasıyla `$IMAGE_V1`, `$IMAGE_V2` ve `$APP_HOST` değerleriyle değiştir.

```bash
cp starter/canary-httproute.yaml canary.local.yaml
nano canary.local.yaml
```

Canary kaynaklarını uygula ve HTTPRoute ağırlıklarını gör.

```bash
kubectl apply -f canary.local.yaml
kubectl -n private-app get httproute devops-app-canary -o yaml
```

Beklenen sonuç: HTTPRoute'ta v1 için `90`, v2 için `10` ağırlığı görünür.

`canary.local.yaml` dosyasını tekrar aç. İlk backend'in `weight` değerini `50`, ikinci backend'in `weight` değerini de `50` yap ve kaydet.

```bash
nano canary.local.yaml
```

Güncellenmiş route'u tekrar uygula ve DNS üzerinden test et.

```bash
kubectl apply -f canary.local.yaml
curl -k "https://${APP_HOST}/healthz"
```

Beklenen sonuç: HTTPRoute ağırlıkları `50/50` olur. Tek bir istekte hangi sürümün döneceği değişebilir; çok sayıda istek atıldığında iki sürümün de yanıt verdiği görülür.
