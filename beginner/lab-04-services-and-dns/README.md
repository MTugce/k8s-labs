# Lab 04: Ağ, Servisler ve Küme İçi DNS Keşfi


## Amaç

Pod'lar yeniden başlatıldığında, güncellendiğinde veya ölçeklendiğinde IP adresleri değişir. Uygulamaların birbirine veya dış dünyanın uygulamalara dinamik IP'lerle erişmesi imkansızdır.

Bu laboratuvarda:
1. Pod IP'lerinin neden güvenilir bir adresleme sağlayamadığını,
2. **ClusterIP Service** ile küme içi sabit IP ve yük dengeleme sağlamayı,
3. **NodePort Service** ile uygulamayı Kubernetes kümesi dışına (host makineye / tarayıcıya) açmayı,
4. **CoreDNS Service Discovery** sayesinde mikroservislerin birbirini IP yerine servis adıyla nasıl otomatik bulduğunu öğreneceksiniz.

---

## Kullanılan Kavramlar

| Nesne / Kavram | Açıklama |
|---|---|
| **Service** | Değişken Pod kümesinin önüne sabit bir sanal IP (ClusterIP) ve DNS adı koyan Kubernetes ağ nesnesidir. |
| **ClusterIP** | Varsayılan servis türüdür; servisi yalnızca küme içerisinden erişilebilir kılar. |
| **NodePort** | Servisi her worker node'un belirlenen statik bir portundan (30000–32767) dış dünyaya açar. |
| **Selector** | Servisin hangi Pod'lara trafik yönlendireceğini belirleyen etiket filtresidir (`app: backend-app`). |
| **CoreDNS** | `servis-adi.namespace.svc.cluster.local` formatındaki isimleri ClusterIP'ye çözen küme içi DNS sunucusudur. |

---

## Çalışma Dizini

```bash
cd ~/k8s-labs/beginner/lab-04-services-and-dns
```

---

## 1. İzole Namespace Oluşturma

```bash
kubectl create namespace beginner-services --dry-run=client -o yaml | kubectl apply -f -
```

---

## 2. Pod IP'lerinin Değişkenliği Sorununu Görme

Önce `starter/service-clusterip.yaml` dosyasındaki Deployment ve Service tanımını inceleyin:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-app
  labels:
    app: backend-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: backend-app
  template:
    metadata:
      labels:
        app: backend-app
    spec:
      containers:
        - name: web
          image: nginx:1.27-alpine
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: backend-service
  labels:
    app: backend-app
spec:
  type: ClusterIP
  selector:
    app: backend-app
  ports:
    - name: http
      port: 80
      targetPort: 80
```

Manifesti uygulayın:

```bash
kubectl apply -f starter/service-clusterip.yaml -n beginner-services
kubectl rollout status deployment/backend-app -n beginner-services
```

Pod'ların IP adreslerini kontrol edin:

```bash
kubectl get pods -n beginner-services -o wide
```

Şimdi Pod'lardan birini silin:

```bash
OLD_POD=$(kubectl get pods -n beginner-services -l app=backend-app -o jsonpath='{.items[0].metadata.name}')
kubectl delete pod "$OLD_POD" -n beginner-services
kubectl get pods -n beginner-services -o wide
```

**Gözlem:** Yeni oluşan Pod farklı bir IP adresi almıştır! Eğer doğrudan Pod IP'sine istek atan bir istemciniz olsaydı bağlantı kopacaktı.

---

## 3. ClusterIP ve Endpoint Eşleşmesini İnceleme

Servisi listeleyin:

```bash
kubectl get service backend-service -n beginner-services
```

**Beklenen sonuç:**
`backend-service` sabit bir `CLUSTER-IP` adresine sahiptir (örn. `10.96.x.x`). Bu IP Pod'lar silinse de asla değişmez!

Servisin arkasındaki sağlıklı Pod IP'lerini otomatik takip eden Endpoint kaydını kontrol edin:

```bash
kubectl get endpoints backend-service -n beginner-services
```

**Beklenen sonuç:** `ENDPOINTS` sütununda mevcut iki Pod'un IP'leri listelenir.

---

## 4. Küme İçinden DNS ve Yük Dengeleme Testi

Küme içinden `backend-service` adına istek atabilmek için geçici bir test konteyneri çalıştıralım:

```bash
kubectl run test-client --image=curlimages/curl:8.12.1 -n beginner-services --restart=Never -- sleep 3600
kubectl wait --for=condition=Ready pod/test-client -n beginner-services --timeout=60s
```

Test konteynerinden servis adına istek gönderin:

```bash
kubectl exec -it -n beginner-services test-client -- curl -I http://backend-service
```

**Beklenen sonuç:**
```text
HTTP/1.1 200 OK
Server: nginx/...
```

Kubernetes CoreDNS, `http://backend-service` sorgusunu otomatik olarak servisin ClusterIP'sine, oradan da rastgele arka plandaki Nginx Pod'larından birine iletmiştir!

Test istemcisini silin:

```bash
kubectl delete pod test-client -n beginner-services
```

---

## 5. NodePort ile Dış Dünyaya Açma

`starter/service-nodeport.yaml` manifestini inceleyin. Kind cluster'ımızın host port yönlendirmesinde (`kind-cluster.yaml`) ayrılan `30086` portunu kullanıyoruz:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: backend-nodeport
  labels:
    app: backend-app
spec:
  type: NodePort
  selector:
    app: backend-app
  ports:
    - name: http
      port: 80
      targetPort: 80
      nodePort: 30086
```

Servisi uygulayın:

```bash
kubectl apply -f starter/service-nodeport.yaml -n beginner-services
kubectl get service backend-nodeport -n beginner-services
```

**Beklenen sonuç:** `PORT(S)` sütununda `80:30086/TCP` görünür.

Host makineden / terminalden doğrudan `30086` portuna istek gönderin:

```bash
curl -I http://127.0.0.1:30086
```

**Beklenen sonuç:** `HTTP/1.1 200 OK`  
Uygulamanız artık küme dışından da erişilebilmektedir!

---

## 6. Servisler Arası İletişim (DNS Service Discovery: Frontend → Backend)

Gerçek dünyada bir web uygulaması (frontend), veritabanına veya API servisine (backend) IP bilmeden yalnızca servis adıyla bağlanır.

`starter/frontend-backend.yaml` dosyasını inceleyin ve uygulayın:

```bash
kubectl apply -f starter/frontend-backend.yaml -n beginner-services
kubectl rollout status deployment/api-backend -n beginner-services
kubectl rollout status deployment/client-frontend -n beginner-services
```

`client-frontend` konteynerinin loglarını izleyin:

```bash
kubectl logs -l app=client-frontend -n beginner-services --tail=5
```

**Beklenen sonuç:**
```text
HTTP/1.1 200 OK
Server: nginx/...
```

İstemci Pod'u hiçbir IP adresi bilmeden `http://api-service` adresi üzerinden sürekli arka uç API'sine erişebilmektedir.

---

## 7. Temizlik (Cleanup)

```bash
kubectl delete namespace beginner-services
```
