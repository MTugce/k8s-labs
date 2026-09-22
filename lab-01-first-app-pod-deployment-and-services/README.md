# İlk Uygulaman: Pod, Deployment ve Service

Bu labı şu klasörde uygulayacaksın:

```bash
cd ~/k8s-labs/lab-01-first-app-pod-deployment-and-services
```

## Bu labda ne yapacaksın?

Tek Pod ile başlayacak, sonra aynı uygulamayı Deployment ile yöneteceksin. Deployment'ın silinen Pod'u yeniden oluşturduğunu görecek ve aynı uygulamaya dört farklı Service türüyle erişeceksin.

## Başlamadan önce

Platform Hazırlığı tamamlanmış olmalıdır. Üç node `Ready` değilse önce eğitmene haber ver.

```bash
kubectl get nodes
```

## 1. YAML yazmadan tek Pod oluştur

`kubectl run`, hızlı test için tek bir Pod oluşturur. Bu Pod'u yöneten bir Deployment yoktur.

Önce Pod'u oluştur.

```bash
kubectl run first-web --image=nginx:1.27-alpine --labels='app=first-web'
```

Sonra Pod'un durumunu ve etiketini gör.

```bash
kubectl get pod first-web --show-labels
```

Beklenen sonuç: Pod kısa süre `ContainerCreating`, sonra `Running` görünür. Etiket sütununda `app=first-web` vardır.

Pod'un image bilgisi ve oluşturulma olaylarını incele.

```bash
kubectl describe pod first-web
```

Beklenen sonuç: `Events` bölümünde image'in çekildiği ve container'ın başlatıldığı görünür.

## 2. Tek Pod ile controller farkını gör

Pod'u sil ve tekrar listele.

```bash
kubectl delete pod first-web
```

Silme işleminden sonra listeyi yenile.

```bash
kubectl get pods
```

Beklenen sonuç: `first-web` geri gelmez. Kubernetes yalnızca istenen durumu yöneten bir controller varsa Pod'u yeniden yaratır.

## 3. Deployment oluştur

Deployment iki Nginx Pod'unun her zaman çalışmasını ister. Kubernetes bunun için otomatik olarak ReplicaSet oluşturur.

Önce uygulama kaynakları için ayrı bir namespace oluştur.

```bash
kubectl create namespace first-app
```

İki Pod isteyen Deployment'ı oluştur.

```bash
kubectl -n first-app create deployment web --image=nginx:1.27-alpine --replicas=2
```

Deployment'ın oluşturduğu kaynakları incele.

```bash
kubectl -n first-app get deployment,replicaset,pods
```

Beklenen sonuç: bir Deployment, bir ReplicaSet ve iki `web-...` Pod'u görünür.

Şimdi istenen Pod sayısını üçe çıkar.

```bash
kubectl -n first-app scale deployment/web --replicas=3
```

Yeni Pod sayısını kontrol et.

```bash
kubectl -n first-app get pods -l app=web
```

Beklenen sonuç: üç Pod `Running` olur.

## 4. Self-healing davranışını kanıtla

Listeden bir Pod adı kopyala ve yalnızca o Pod'u sil.

Önce silmek istediğin Pod'un adını bul.

```bash
kubectl -n first-app get pods -l app=web
```

Listeden kopyaladığın gerçek Pod adıyla yalnızca o Pod'u sil.

```bash
kubectl -n first-app delete pod POD_ADI
```

Deployment'ın yerine yeni Pod açmasını canlı izle. `-w`, listede değişiklik olduğunda yeni satır göstermesini sağlar.

```bash
kubectl -n first-app get pods -l app=web -w
```

Beklenen sonuç: silinen Pod yerine farklı isimli yeni bir Pod oluşur; toplam sayı tekrar üçe gelir. İzlemeyi `Ctrl+C` ile bitir.

## 5. ClusterIP Service oluştur

Pod IP'leri değişebilir. ClusterIP Service, Pod'lara sabit bir DNS adı verir ve yalnızca cluster içinden erişilir.

Deployment'ın Pod'larını `web-clusterip` adlı Service arkasına al.

```bash
kubectl -n first-app expose deployment web --name=web-clusterip --port=80
```

Oluşan Service'i kontrol et.

```bash
kubectl -n first-app get service web-clusterip
```

Cluster içinden test yapabilmek için `curl-inside` adlı geçici Pod oluştur. `sleep 3600`, Pod'un bir saat açık kalmasını sağlar.

```bash
kubectl -n first-app run curl-inside \
  --image=curlimages/curl:8.12.1 \
  --restart=Never \
  -- sleep 3600
```

Pod'un çalışır duruma gelmesini bekle.

```bash
kubectl -n first-app wait --for=condition=Ready pod/curl-inside --timeout=90s
```

Sonra test Pod'unun içinden Service adına HTTP isteği gönder.

```bash
kubectl -n first-app exec curl-inside -- curl -I http://web-clusterip
```

Test bitince geçici Pod'u sil.

```bash
kubectl -n first-app delete pod curl-inside
```

Beklenen sonuç: HTTP isteği `HTTP/1.1 200 OK` döndürür. `web-clusterip`, Pod IP'si yerine Service adını kullanır.

## 6. NodePort, ExternalName ve LoadBalancer türlerini dene

Hazır manifest aynı Deployment için üç Service türü daha oluşturur.

```bash
kubectl apply -f ~/k8s-labs/lab-01-first-app-pod-deployment-and-services/starter/service-types.yaml
kubectl -n first-app get services
```

Beklenen sonuç:

- `web-nodeport` satırında `30086` görünür.
- `external-docs`, `kubernetes.io` için DNS takma adıdır; Pod seçmez.
- `web-loadbalancer` için Kind üzerinde `EXTERNAL-IP` genellikle `pending` kalır. Cloud sağlayıcı load balancer olmadığı için bu normaldir.

NodePort ile sunucunun IP adresinden eriş.

```bash
curl -I http://SUNUCU_IP:30086
```

Beklenen sonuç: `HTTP/1.1 200 OK`. Bu labın sonunda Pod, Deployment, self-healing, scale ve dört Service türünü uyguladın.
