# Lab 09: Uçtan Uca Mikroservis Dağıtımı (Capstone Projesi)

## Amaç

Bu laboratuvar, Beginner serisi boyunca öğrendiğiniz tüm temel kavramları (Pod, Deployment, Service, ConfigMap, Secret, PersistentVolumeClaim ve StatefulSet) tek bir gerçek dünya üretim mimarisinde birleştiren **bitiş projesidir (Capstone Project)**.

Bu projede:
1. **Docker Hub Registry Entegrasyonu:** Public ve Private repository'lerin farkını yaşayacak, kilitli bir private repodan (`hbayraktar/devops-app`) imaj çekerken oluşan yetki hatasını (`ErrImagePull`) gözlemleyecek ve `imagePullSecrets` ile yetkili erişim sağlayacaksınız.
2. **Konfigürasyon ve Güvenlik:** Uygulama parametrelerini **ConfigMap**, veritabanı parolalarını **Secret** nesneleriyle deklaratif olarak yöneteceksiniz.
3. **Durumlu Arka Uç (StatefulSet & PVC):** MySQL veritabanını dinamik disk tahsisi sağlayan **PVC** ile ayağa kaldıracak, cluster içi **Headless Service** ile web katmanına bağlayacaksınız.
4. **Ön Yüz Dağıtımı ve Dış Erişim:** Web uygulamasını 2 replikalı bir **Deployment** olarak çalıştıracak ve **NodePort (30088)** servisi üzerinden cluster dışına açacaksınız.
5. **Kalıcılık Kanıtı:** Veritabanına kayıt ekleyip Pod'u silecek; yeni Pod ayağa kalktığında verilerin PVC sayesinde aynen korunduğunu test edeceksiniz.

---

## Proje Mimarisi

```text
                                [Docker Hub]
                                     │
           ┌─────────────────────────┴────────────────────────┐
           │                                                  │
   [Public Repository]                                [Private Repository]
(devops-app-pub:nginx-1.0)                          (devops-app:nginx-1.0)
     Doğrudan Çekilir                                          │
                                                [Secret: dockerhub-cred]
                                                               │
                                                               ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ Namespace: beginner-capstone                                                │
│                                                                             │
│   [ConfigMap: app-config] ──┐                                               │
│   [Secret: db-secret]     ──┼──> [Deployment: web-app] (2 Replicas)        │
│                             │             │                                 │
│                             │             ▼                                 │
│                             │    [Service: web-service] (NodePort: 30088)   │
│                             │             │                                 │
│                             │             ▼                                 │
│                             │    Dış Erişim: http://localhost:30088         │
│                             │                                               │
│                             └──> [StatefulSet: mysql]                       │
│                                           │                                 │
│                                  [PVC: mysql-data] (1Gi Kalıcı Disk)        │
│                                           │                                 │
│                                  [Service: mysql-service] (ClusterIP: 3306) │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Çalışma Dizini

```bash
cd ~/k8s-labs/beginner/lab-09-capstone-project
```

---

## 1. İzole Namespace Oluşturma

Tüm proje kaynaklarını izole etmek için `beginner-capstone` namespace'ini oluşturun:

```bash
kubectl create namespace beginner-capstone --dry-run=client -o yaml | kubectl apply -f -
```

---

## 2. Docker Hub Registry ve İmaj Yetkilendirmesi (Public vs Private)

Docker Hub üzerinde iki tür repository bulunur:
* **Public Repo (`devops-app-pub`):** Herkes tarafından oturum açmadan çekilebilir.
* **Private Repo (`devops-app`):** Yalnızca yetkili hesaplar tarafından çekilebilir.

### Adım 2.1: Public İmajı Çekme Testi

Herhangi bir şifre tanımlamadan public imajı test edin:

```bash
kubectl run pub-test --image=hbayraktar/devops-app-pub:nginx-1.0 -n beginner-capstone
kubectl wait --for=condition=Ready pod/pub-test -n beginner-capstone --timeout=60s
```

Pod'un başarıyla `Running` durumuna geldiğini görün:

```bash
kubectl get pod pub-test -n beginner-capstone
```

Test pod'unu silin:

```bash
kubectl delete pod pub-test -n beginner-capstone
```

### Adım 2.2: Private İmajı Yetkisiz Çekmeyi Deneme (Beklenen Hata!)

Şimdi yetki vermeden doğrudan private depodan bir Pod çalıştırmayı deneyin:

```bash
kubectl run priv-fail-test --image=hbayraktar/devops-app:nginx-1.0 --restart=Never -n beginner-capstone
```

Pod durumunu inceleyin:

```bash
kubectl get pod priv-fail-test -n beginner-capstone
```

`STATUS` sütununda `ErrImagePull` veya `ImagePullBackOff` göreceksiniz! Hata detayını `describe` ile inceleyin:

```bash
kubectl describe pod priv-fail-test -n beginner-capstone | grep -E "Failed|Error"
```

Çıktıda Docker Hub'ın erişim izni vermediğini (`pull access denied` veya `unauthorized`) gözlemleyin. Hatalı pod'u temizleyin:

```bash
kubectl delete pod priv-fail-test -n beginner-capstone
```

### Adım 2.3: `docker-registry` Secret'ı ile Kimlik Tanımlama

Kubernetes kubelet'in Docker Hub private deposundan imaj çekebilmesi için bir kimlik kartı (`docker-registry` türünde Secret) oluşturun:

```bash
kubectl create secret docker-registry dockerhub-cred \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=hbayraktar \
  --docker-password=dckr_pat_5w0ubBN7WzUYxn2PNtlQEFvw2Ss \
  -n beginner-capstone
```

Secret nesnesini listeleyin:

```bash
kubectl get secret dockerhub-cred -n beginner-capstone
```

---

## 3. Konfigürasyon ve Güvenlik (ConfigMap & Secret)

### Adım 3.1: ConfigMap Manifestini İnceleme ve Uygulama

`starter/configmap.yaml` dosyasını inceleyin. Bu dosya veritabanı host adresi, port, veritabanı adı ve ortam bilgilerini içerir:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  labels:
    app.kubernetes.io/part-of: capstone-project
data:
  DB_HOST: "mysql-service"
  DB_PORT: "3306"
  DB_NAME: "devopsdb"
  ENVIRONMENT: "production"
  APP_TITLE: "DevOps Practitioner Capstone Web App"
```

Manifesti uygulayın:

```bash
kubectl apply -f starter/configmap.yaml -n beginner-capstone
```

### Adım 3.2: Secret Manifestini İnceleme ve Uygulama

`starter/secret.yaml` dosyasını inceleyin. Veritabanı `root` ve kullanıcı parolaları burada tanımlanmıştır:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-secret
  labels:
    app.kubernetes.io/part-of: capstone-project
type: Opaque
stringData:
  MYSQL_ROOT_PASSWORD: "RootPassword123!"
  MYSQL_PASSWORD: "UserPassword123!"
  MYSQL_USER: "devopsuser"
```

Manifesti uygulayın:

```bash
kubectl apply -f starter/secret.yaml -n beginner-capstone
```

Oluşturulan konfigürasyonları teyit edin:

```bash
kubectl get configmap,secret -n beginner-capstone
```

---

## 4. Veritabanı Katmanı: MySQL StatefulSet ve PVC

Veritabanları durum bilgisi (state) tuttuğu için rastgele Pod'lar yerine kararlı kimliklere (`mysql-0`) ve her replika için bağımsız bir kalıcı diske (`volumeClaimTemplates`) ihtiyaç duyar.

`starter/mysql-statefulset.yaml` dosyasını inceleyin:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mysql-service
  labels:
    app: mysql
spec:
  ports:
  - port: 3306
    name: mysql
  clusterIP: None
  selector:
    app: mysql
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
spec:
  serviceName: mysql-service
  replicas: 1
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - name: mysql
        image: mysql:8.0-debian
        ports:
        - containerPort: 3306
          name: mysql
        env:
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: MYSQL_ROOT_PASSWORD
        - name: MYSQL_DATABASE
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: DB_NAME
        readinessProbe:
          exec:
            command: ["mysqladmin", "ping", "-h", "127.0.0.1", "-u", "root", "-pRootPassword123!"]
          initialDelaySeconds: 10
          periodSeconds: 3
          timeoutSeconds: 2
        volumeMounts:
        - name: mysql-data
          mountPath: /var/lib/mysql
  volumeClaimTemplates:
  - metadata:
      name: mysql-data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 1Gi
```

Manifesti cluster'a uygulayın:

```bash
kubectl apply -f starter/mysql-statefulset.yaml -n beginner-capstone
```

MySQL ilk kurulumda veritabanı dosyalarını ilklendirdiği için hazır olması yaklaşık 15-20 saniye sürebilir. Pod'un hazır olmasını bekleyin:

```bash
kubectl wait --for=condition=Ready pod/mysql-0 -n beginner-capstone --timeout=120s
```

Kalıcı diskin (PVC) otomatik oluşturulup `Bound` olduğunu doğrulayın:

```bash
kubectl get pvc -n beginner-capstone
```

---

## 5. Web Katmanı ve Dış Erişim: Deployment ve NodePort Service

### Adım 5.1: Web Deployment Manifestini İnceleme

`starter/web-deployment.yaml` manifestinde 2 replika tanımlıdır. Private imajı çekmek için `imagePullSecrets: [name: dockerhub-cred]` ve ortam ayarlarını aktarmak için `envFrom` tanımlanmıştır:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
  labels:
    app: web-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web-app
  template:
    metadata:
      labels:
        app: web-app
    spec:
      imagePullSecrets:
      - name: dockerhub-cred
      containers:
      - name: web
        image: hbayraktar/devops-app:nginx-1.0
        ports:
        - containerPort: 80
        envFrom:
        - configMapRef:
            name: app-config
```

### Adım 5.2: Web Service Manifestini İnceleme

`starter/web-service.yaml` manifesti web uygulamasını Kind cluster mimarimizde (`kind-cluster.yaml`) ayrılan **30088** NodePort portundan dış dünyaya açar:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web-service
spec:
  type: NodePort
  selector:
    app: web-app
  ports:
  - name: http
    port: 80
    targetPort: 80
    nodePort: 30088
```

Manifestleri uygulayın:

```bash
kubectl apply -f starter/web-deployment.yaml -n beginner-capstone
kubectl apply -f starter/web-service.yaml -n beginner-capstone
kubectl rollout status deployment/web-app -n beginner-capstone --timeout=90s
```

Pod'ların çalıştığını kontrol edin:

```bash
kubectl get pods -n beginner-capstone -l app=web-app
```

**Beklenen sonuç:** Her iki web pod'u da `Running (1/1)` durumundadır.

### Adım 5.3: Web Uygulamasına Dışarıdan Erişme (NodePort 30088)

Host terminalinden doğrudan NodePort portuna istek gönderin:

```bash
curl -I http://127.0.0.1:30088
```

Web sayfasının içeriğini görüntüleyin:

```bash
curl -s http://127.0.0.1:30088
```

**Beklenen sonuç:**
```html
<!doctype html>
<html lang="tr">
  <head>
    <meta charset="utf-8">
    <title>Docker Hub Access Lab</title>
  </head>
  <body>
    <h1>Docker Hub access lab</h1>
    <p>Public ve private image yayını doğrulandı.</p>
  </body>
</html>
```

Tarayıcınızdan `http://<SANAL_MAKİNE_IP>:30088` adresine giderek arayüzü görsel olarak da açabilirsiniz!

---

## 6. Kalıcı Veri (PVC) ve Self-Healing Doğrulaması

Uygulamamız çalışıyor, peki veritabanı podu çökerse veriler korunacak mı?

### Adım 6.1: Veritabanına Veri Yazma

MySQL içine bağlanarak bir tablo oluşturalım ve iki müşteri kaydı ekleyelim:

```bash
kubectl exec -n beginner-capstone mysql-0 -- mysql -h 127.0.0.1 -u root -pRootPassword123! devopsdb -e "
CREATE TABLE musteri_kayitlari (id INT AUTO_INCREMENT PRIMARY KEY, ad VARCHAR(100), sirket VARCHAR(100));
INSERT INTO musteri_kayitlari (ad, sirket) VALUES ('Ali Can', 'IBB'), ('Fatma Demir', 'Tech Istanbul');
"
```

Eklenen veriyi okuyun:

```bash
kubectl exec -n beginner-capstone mysql-0 -- mysql -h 127.0.0.1 -u root -pRootPassword123! devopsdb -e "SELECT * FROM musteri_kayitlari;"
```

### Adım 6.2: Pod'u Silerek Felaket Testi Yapma

Şimdi `mysql-0` pod'unu zorla silin:

```bash
kubectl delete pod mysql-0 -n beginner-capstone --wait=true
```

StatefulSet Controller anında yeni bir `mysql-0` pod'u oluşturacaktır. Pod'un tekrar `Ready` duruma gelmesini bekleyin:

```bash
kubectl wait --for=condition=Ready pod/mysql-0 -n beginner-capstone --timeout=120s
```

### Adım 6.3: Verilerin Korunduğunu Kanıtlama

Yeni doğan `mysql-0` pod'u eski PVC'yi (`mysql-data-mysql-0`) otomatik olarak yeniden bağlamıştır. Kayıtları tekrar sorgulayın:

```bash
kubectl exec -n beginner-capstone mysql-0 -- mysql -h 127.0.0.1 -u root -pRootPassword123! devopsdb -e "SELECT * FROM musteri_kayitlari;"
```

**Beklenen sonuç:**
```text
id	ad	sirket
1	Ali Can	IBB
2	Fatma Demir	Tech Istanbul
```

Veriler eksiksiz olarak korunmuştur! Pod silinse veya çökse dahi veritabanı durumu asla kaybolmaz.

---

## 7. Temizlik

Laboratuvar kaynaklarını temizlemek için:

```bash
kubectl delete namespace beginner-capstone
```

Namespace silindiğinde Deployment, StatefulSet, Pod'lar, Servisler ve PVC'ler otomatik olarak temizlenir.

---

## Capstone Projesi Özeti

Tebrikler! Beginner seviyesinin tüm bileşenlerini uçtan uca tek bir üretim mimarisinde birleştirdiniz:

| Katman | Kullanılan Nesne | Gerçek Hayattaki Karşılığı |
|---|---|---|
| **Kimlik Doğrulama** | `Secret (docker-registry)` | Kurumsal özel imaj deposundan (Docker Hub / Harbor / ECR / GCR) güvenli imaj çekme |
| **Konfigürasyon** | `ConfigMap` | Ortam ayarlarının (Environment, DB Host) koddan bağımsız yönetilmesi |
| **Güvenlik** | `Secret (Opaque)` | Hassas şifrelerin ve token'ların güvenli saklanması |
| **Ön Yüz (Web)** | `Deployment (Replicas: 2)` | Kesintisiz çalışan, ölçeklenebilir ve kendini onaran web uygulaması |
| **Dış Ağ Erişimi** | `Service (NodePort: 30088)` | Dış dünyadan tarayıcı veya curl ile web uygulamasına erişim |
| **Arka Yüz (Veritabanı)** | `StatefulSet & Headless Service` | Kararlı DNS adı (`mysql-service:3306`) ile çalışan ilişkisel veritabanı |
| **Kalıcı Depolama** | `PersistentVolumeClaim (PVC)` | Pod çökse veya silinse dahi veritabanı kayıtlarının korunması |
