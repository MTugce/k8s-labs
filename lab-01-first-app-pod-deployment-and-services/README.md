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

```bash
kubectl run first-web --image=nginx:1.27-alpine --labels='app=first-web'
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
kubectl get pods
```

Beklenen sonuç: `first-web` geri gelmez. Kubernetes yalnızca istenen durumu yöneten bir controller varsa Pod'u yeniden yaratır.

## 3. Deployment oluştur

Deployment iki Nginx Pod'unun her zaman çalışmasını ister. Kubernetes bunun için otomatik olarak ReplicaSet oluşturur.

```bash
kubectl create namespace first-app
kubectl -n first-app create deployment web --image=nginx:1.27-alpine --replicas=2
kubectl -n first-app get deployment,replicaset,pods
```

Beklenen sonuç: bir Deployment, bir ReplicaSet ve iki `web-...` Pod'u görünür.

Şimdi istenen Pod sayısını üçe çıkar.

```bash
kubectl -n first-app scale deployment/web --replicas=3
kubectl -n first-app get pods -l app=web
```

Beklenen sonuç: üç Pod `Running` olur.

## 4. Self-healing davranışını kanıtla

Listeden bir Pod adı kopyala ve yalnızca o Pod'u sil.

```bash
kubectl -n first-app get pods -l app=web
kubectl -n first-app delete pod POD_ADI
kubectl -n first-app get pods -l app=web -w
```

Beklenen sonuç: silinen Pod yerine farklı isimli yeni bir Pod oluşur; toplam sayı tekrar üçe gelir. İzlemeyi `Ctrl+C` ile bitir.

## 5. ClusterIP Service oluştur

Pod IP'leri değişebilir. ClusterIP Service, Pod'lara sabit bir DNS adı verir ve yalnızca cluster içinden erişilir.

```bash
kubectl -n first-app expose deployment web --name=web-clusterip --port=80
kubectl -n first-app get service web-clusterip
kubectl -n first-app run curl-inside --rm -it --restart=Never \
  --image=curlimages/curl:8.12.1 -- curl -I http://web-clusterip
```

Beklenen sonuç: son komut `HTTP/1.1 200 OK` döndürür. `web-clusterip`, Pod IP'si yerine Service adını kullanır.

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
