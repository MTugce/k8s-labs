# * WordPress ile Helm Operasyonlarını Öğren

> **Seviye:** Advanced
> **Tahmini süre:** 60–75 dakika
> **Eğitim durumu:** İsteğe bağlı

## Amaç

Helm ile paket yönetiminin mantığını; repository ekleme, chart anatomisini inceleme, özel `values` ile kurulum, güncelleme (upgrade), geri alma (rollback) ve kaldırma (uninstall) adımlarını uygulamalı olarak öğrenmek.

## Kullanılan Kubernetes nesneleri

- **Namespace:** WordPress bileşenlerini izole eder (`wordpress-lab`).
- **Deployment & StatefulSet:** WordPress ve MariaDB veritabanı Pod'larını yönetir.
- **Service & PVC:** Pod'lar arası iletişimi ve disklerde kalıcı veri saklamayı sağlar.

## Çalışma dizini

```bash
cd ~/k8s-labs/advanced/lab-05-helm-operations
```

---

## 1. Helm Repository Ekle ve Ara

Helm repository, chart paketlerinin tutulduğu uzak depodur.

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm search repo bitnami/wordpress --version 34.0.4
```

Beklenen sonuç: `bitnami/wordpress` chart'ı ve `34.0.4` sürüm bilgisi listelenir.

---

## 2. Helm Chart'ı İndir ve Anatomisini İncele

Bir Helm chart'ın içinde ne olduğunu görmek için paketi klasör olarak lokale indir:

```bash
helm pull bitnami/wordpress --version 34.0.4 --untar
ls -la wordpress/
```

İndirilen klasör yapısında şunları görürsün:
- **`Chart.yaml`:** Chart'ın adı, açıklaması ve sürüm metadata'sı.
- **`values.yaml`:** Tüm varsayılan yapılandırma parametreleri.
- **`templates/`:** Kubernetes manifest şablonları (`deployment.yaml`, `svc.yaml`, `pvc.yaml` vb.):
  ```bash
  ls -la wordpress/templates/
  ```
- **`charts/`:** Alt bağımlılıklar (bu chart için MariaDB veritabanı).

---

## 3. Özel Değerler (`values.yaml`) ile WordPress'i Kur

Tüm varsayılan değerleri değiştirmek yerine, sadece değiştirmek istediğimiz alanları `starter/values.yaml` dosyasında belirttik:

```yaml
service:
  type: ClusterIP                       # Host portunu işgal etmemek için ClusterIP
wordpressBlogName: "Kubernetes Helm Lab v1"  # Blog başlığı
mariadb:
  primary:
    persistence:
      enabled: true
      storageClass: standard            # Kind kümesinin yerel depolama sınıfı
```

Bu değerleri kullanarak WordPress'i kur:

```bash
kubectl create namespace wordpress-lab --dry-run=client -o yaml | kubectl apply -f -

helm install wordpress bitnami/wordpress \
  --version 34.0.4 \
  --namespace wordpress-lab \
  --values starter/values.yaml \
  --wait --timeout 5m
```

Kurulum durumunu kontrol et:

```bash
helm list -n wordpress-lab
kubectl -n wordpress-lab get pods,pvc,svc
```

Beklenen sonuç: `wordpress` ve `wordpress-mariadb-0` Pod'ları `Running` olur, PVC'ler `Bound` durumuna geçer.

---

## 4. Giriş Parolasını Al ve Uygulamaya Eriş

WordPress yönetici parolası kurulum sırasında otomatik üretilerek Secret içine kaydedilmiştir.

Parolayı Secret'tan çekip ekrana yazdır:

```bash
export WP_PASSWORD=$(kubectl -n wordpress-lab get secret wordpress -o jsonpath='{.data.wordpress-password}' | base64 -d)
echo "Kullanıcı Adı: user"
echo "WordPress Parolası: $WP_PASSWORD"
```

Uygulamaya erişmek için port-forward başlat (arka planda çalıştır):

```bash
kubectl -n wordpress-lab port-forward service/wordpress 8088:80 &
export WORDPRESS_PORT_FORWARD_PID=$!
```

HTTP yanıtını doğrula:

```bash
curl -I http://127.0.0.1:8088
```

Beklenen sonuç: `HTTP/1.1 200 OK` veya `302 Found` döner. Tarayıcınızdan `http://SUNUCU_IP:8088` (veya yerelde `http://localhost:8088`) adresine giderek `user` ve yukarıda aldığınız parola ile WordPress paneline giriş yapabilirsiniz.

---

## 5. Release Güncelleme (`helm upgrade`)

Uygulamanın ayarlarını değiştirmek için YAML'ı elle düzenlemek yerine Helm upgrade kullanırız. Blog başlığını `v2` yapalım:

```bash
helm upgrade wordpress bitnami/wordpress \
  --version 34.0.4 \
  --namespace wordpress-lab \
  --values starter/values.yaml \
  --set wordpressBlogName="Kubernetes Helm Lab v2" \
  --wait
```

Revizyon geçmişini incele:

```bash
helm history wordpress -n wordpress-lab
```

Beklenen sonuç: `REVISION: 1` ve `REVISION: 2` listelenir.

---

## 6. Sürümü Geri Al (`helm rollback`)

Yapılan değişiklikten vazgeçildiğinde bir önceki stabil revizyona saniyeler içinde dönülebilir:

```bash
helm rollback wordpress 1 --namespace wordpress-lab --wait
helm history wordpress -n wordpress-lab
```

Beklenen sonuç: Yeni bir revizyon oluşur (`REVISION: 3`) ve uygulamanın ayarları 1. revizyondaki durumuna (`v1`) döner.

---

## 7. Temizlik (`helm uninstall`)

Tüm WordPress ve veritabanı bileşenlerini tek bir komutla sil:

```bash
helm uninstall wordpress --namespace wordpress-lab
kubectl delete namespace wordpress-lab
```

Arka plandaki port-forward işlemini kapat:

```bash
kill "$WORDPRESS_PORT_FORWARD_PID" 2>/dev/null || true
```

Beklenen sonuç: `release "wordpress" uninstalled` çıktısı alınır ve kaynaklar temizlenir.

## Başarı kriterleri

- Helm repository ve chart kavramlarını açıklayabiliyorsunuz.
- Özel values dosyasıyla release kurdunuz.
- Release'i upgrade edip revision geçmişini gördünüz.
- Rollback ve uninstall işlemlerini tamamladınız.
