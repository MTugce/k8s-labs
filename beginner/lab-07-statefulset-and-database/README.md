# Lab 07: Durumlu Uygulamalar (StatefulSet ve MySQL Veritabanı)

## Amaç

Stateless (durumsuz) web uygulamaları için Deployment mükemmel bir çözümdür; ancak MySQL, PostgreSQL veya MongoDB gibi veritabanları söz konusu olduğunda Deployment yetersiz kalır. Veritabanlarının rastgele değil, tahmin edilebilir sabit kimliklere (`mysql-0`, `mysql-1`) ve her kopyanın kendine ait bağımsız bir kalıcı diske ihtiyacı vardır.

Bu laboratuvarda:
1. Veritabanlarının neden Deployment yerine **StatefulSet** ile çalıştırıldığını,
2. **Headless Service (`clusterIP: None`)** ile her bir Pod kopyasına nasıl doğrudan DNS adı atandığını,
3. **`volumeClaimTemplates`** mekanizması ile her Pod için otomatik bağımsız PVC üretimini,
4. Pod silinse dahi yeni oluşturulan Pod'un aynı ismi alarak **aynı diski ve veriyi** koruduğunu adım adım öğreneceksiniz.

---

## Kullanılan Kavramlar

| Nesne / Kavram | Açıklama |
|---|---|
| **StatefulSet** | Durum bilgisi saklayan uygulamalar için tasarlanmış controller nesnesidir. Pod'lara `isim-0`, `isim-1` şeklinde sıralı ve kalıcı kimlik verir. |
| **Headless Service** | `clusterIP: None` olarak tanımlanan servistir. Ortak bir sanal IP arkasında yük dağıtmak yerine, her Pod için doğrudan tekil bir DNS A kaydı (`mysql-0.mysql-headless`) üretir. |
| **volumeClaimTemplates** | StatefulSet içindeki her Pod replikası için otomatik olarak `disk-adi-pod-adi` formatında bağımsız ve kalıcı bir PVC oluşturan şablondur. |
| **Sıralı Dağıtım (Ordered Deployment)** | StatefulSet Pod'ları rastgele aynı anda değil; sırayla (0'dan başlayarak) ayağa kaldırır ve bir önceki Pod tamamen hazır (`Ready`) olmadan sonrakini başlatmaz. |

---

## Çalışma Dizini

```bash
cd ~/k8s-labs/beginner/lab-07-statefulset-and-database
```

---

## 1. İzole Namespace Oluşturma

Çalışmalarımızı diğer laboratuvarlardan ayırmak için `beginner-statefulset` namespace'ini oluşturalım:

```bash
kubectl create namespace beginner-statefulset --dry-run=client -o yaml | kubectl apply -f -
```

---

## 2. Neden Deployment Veritabanı İçin Uygun Değildir?

Deployment nesnesi web sunucuları gibi birbiriyle tıpatıp aynı ve durumu olmayan (stateless) uygulamalar için tasarlanmıştır:
- Pod isimleri rastgeledir (`web-677cf7b45d-6dqn9`).
- Pod'lar rastgele sıralarla açılır ve kapanır.
- Bir Deployment'a PVC bağlandığında, tüm kopyalar aynı diski paylaşmaya çalışır. Oysa veritabanı motorları (MySQL/PostgreSQL) aynı veri dizinine birden fazla kopya yazmaya çalıştığında dosya kilitlenme hataları üretir ve veritabanı çöker.

**StatefulSet Çözümü:**
- Her Pod sabit ve tahmin edilebilir bir ad alır (`mysql-0`, `mysql-1`).
- Her Pod'a `volumeClaimTemplates` ile tamamen bağımsız bir disk tahsis edilir (`mysql-data-mysql-0`, `mysql-data-mysql-1`).
- `mysql-0` silinse bile, yerine gelen yeni Pod yine `mysql-0` adını alır ve **tam olarak aynı diski** bağlar.

---

## 3. Headless Service ve StatefulSet Manifestini İnceleme

`starter/mysql-statefulset.yaml` manifestini inceleyin:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mysql-headless
  labels:
    app: mysql
spec:
  clusterIP: None
  selector:
    app: mysql
  ports:
    - name: mysql
      port: 3306
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
spec:
  serviceName: mysql-headless
  replicas: 2
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
          image: mysql:8.0
          env:
            - name: MYSQL_ROOT_PASSWORD
              value: "RootSecretPassword123"
            - name: MYSQL_DATABASE
              value: "devops_db"
          ports:
            - name: mysql
              containerPort: 3306
          readinessProbe:
            exec:
              command: ["mysqladmin", "ping", "-h", "127.0.0.1", "-u", "root", "-pRootSecretPassword123"]
            initialDelaySeconds: 5
            periodSeconds: 2
            timeoutSeconds: 2
          volumeMounts:
            - name: mysql-data
              mountPath: /var/lib/mysql
  volumeClaimTemplates:
    - metadata:
        name: mysql-data
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: standard
        resources:
          requests:
            storage: 1Gi
```

Manifestteki kritik detaylar:
- `clusterIP: None`: Servisin bir ClusterIP almasını engeller, doğrudan Headless Service moduna geçirir.
- `serviceName: mysql-headless`: StatefulSet'i bu servise bağlar; DNS kayıtlarının oluşturulmasını sağlar.
- `volumeClaimTemplates`: Her replika için 1Gi boyutunda bağımsız disk üretilmesini talimatlandırır.
- `readinessProbe`: MySQL sunucusu gerçekten istemci kabul etmeye hazır olana kadar Pod'u `Ready` yapmaz.

---

## 4. Manifesti Uygulama ve Sıralı Başlatmayı İzleme

Manifesti kümeye uygulayın:

```bash
kubectl apply -f starter/mysql-statefulset.yaml -n beginner-statefulset
```

Pod'ların oluşturulma sürecini canlı izleyin:

```bash
kubectl get pods -n beginner-statefulset -w
```

*(Canlı izlemeyi durdurmak için `Ctrl + C` tuşlarına basın).*

**Gözlem:**
1. Önce `mysql-0` oluşturulur.
2. `mysql-0` tamamen `Running` ve `1/1 Ready` olana kadar `mysql-1` kesinlikle başlatılmaz!
3. `mysql-0` hazır olduğunda `mysql-1` oluşturulur.

Her iki Pod'un da hazır olmasını bekleyin:

```bash
kubectl wait --for=condition=Ready pod/mysql-0 -n beginner-statefulset --timeout=120s
kubectl wait --for=condition=Ready pod/mysql-1 -n beginner-statefulset --timeout=120s
```

Pod listesini kontrol edin:

```bash
kubectl get pods -n beginner-statefulset
```

**Beklenen sonuç:**
```text
NAME      READY   STATUS    RESTARTS   AGE
mysql-0   1/1     Running   0          45s
mysql-1   1/1     Running   0          25s
```

---

## 5. Otomatik Üretilen Bağımsız Diskleri (PVC) İnceleme

StatefulSet'in arka planda oluşturduğu PVC'leri listeleyin:

```bash
kubectl get pvc -n beginner-statefulset
```

**Beklenen sonuç:**
```text
NAME                 STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
mysql-data-mysql-0   Bound    pvc-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx   1Gi        RWO            standard       1m
mysql-data-mysql-1   Bound    pvc-yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy   1Gi        RWO            standard       45s
```

Her replika (`mysql-0` ve `mysql-1`) için tamamen bağımsız, ayrı birer kalıcı disk (PV/PVC) tahsis edilmiştir.

---

## 6. Headless Service ile Pod DNS Adlarını Keşfetme

Headless Service sayesinde her Pod'un küme içinde sabit bir DNS adı vardır:
- `mysql-0.mysql-headless.beginner-statefulset.svc.cluster.local`
- `mysql-1.mysql-headless.beginner-statefulset.svc.cluster.local`

`mysql-1` konteyneri içinden `mysql-0` DNS adını sorgulayarak doğrulayın:

```bash
kubectl exec -it -n beginner-statefulset mysql-1 -- getent hosts mysql-0.mysql-headless
```

**Beklenen sonuç:** `mysql-0`'ın IP adresi ve tam DNS adı başarıyla listelenir.

---

## 7. Canlı Veri Yazma (MySQL Tablo ve Veri Ekleme)

`mysql-0` veritabanına bağlanıp `devops_db` içinde bir tablo oluşturalım ve veri ekleyelim:

```bash
kubectl exec -n beginner-statefulset mysql-0 -- mysql -h 127.0.0.1 -u root -pRootSecretPassword123 devops_db -e "
CREATE TABLE ogrenciler (id INT AUTO_INCREMENT PRIMARY KEY, ad VARCHAR(50), notu INT);
INSERT INTO ogrenciler (ad, notu) VALUES ('Ahmet', 95), ('Zeynep', 100);
"
```

Eklenen veriyi okuyun:

```bash
kubectl exec -n beginner-statefulset mysql-0 -- mysql -h 127.0.0.1 -u root -pRootSecretPassword123 devops_db -e "SELECT * FROM ogrenciler;"
```

**Beklenen sonuç:**
```text
id	ad	notu
1	Ahmet	95
2	Zeynep	100
```

---

## 8. Kalıcı Kimlik ve Veri Koruma Kanıtı (Pod Silme Testi)

Şimdi `mysql-0` Pod'unu elle tamamen silelim:

```bash
kubectl delete pod mysql-0 -n beginner-statefulset
```

StatefulSet'in anında yeni bir `mysql-0` üretmesini izleyin:

```bash
kubectl wait --for=condition=Ready pod/mysql-0 -n beginner-statefulset --timeout=120s
```

Yeni oluşturulan `mysql-0` içindeki verileri tekrar sorgulayın:

```bash
kubectl exec -n beginner-statefulset mysql-0 -- mysql -h 127.0.0.1 -u root -pRootSecretPassword123 devops_db -e "SELECT * FROM ogrenciler;"
```

**Beklenen sonuç:**
```text
id	ad	notu
1	Ahmet	95
2	Zeynep	100
```

Pod tamamen silinip yeniden üretilmesine rağmen, StatefulSet aynı isimli `mysql-0` kimliğini korumuş ve `mysql-data-mysql-0` diskini yeniden bağlayarak verilerimizin hiçbir kayba uğramadan korunmasını sağlamıştır!

---

## 9. Temizlik (Cleanup)

```bash
kubectl delete namespace beginner-statefulset
```

*(Not: StatefulSet silindiğinde veri güvenliği gereği PVC'ler korunabilir; namespace silindiğinde tüm PVC'ler ve ayrılan diskler temizlenir).*
