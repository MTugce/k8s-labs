# WordPress ile Helm Operasyonlarını Öğren

| Seviye | Tahmini Süre | Profil / Araçlar | Açık Portlar |
| --- | --- | --- | --- |
| Orta | 55 dk | Helm, kubectl | Yerel `8088` |

## Bu labda ne yapacaksın?

WordPress'i Helm chart ile kuracak, release değerlerini inceleyecek, upgrade ve rollback yapacaksın. Bu uygulama Helm operasyonlarını öğrenmek içindir; lab sonunda yalnızca WordPress release'i kaldırılacaktır. Prometheus ve Grafana sonraki labda kurulacak ve kurs boyunca kalacaktır.

## 1. Helm repository kavramını gör

Repository, Helm chart paketlerinin indeksidir. Önce Bitnami repository'yi ekle ve içeriğini ara.

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm repo list
helm search repo bitnami/wordpress
```

Beklenen sonuç: `bitnami/wordpress` chart adı ve sürümü görünür.

## 2. Chart'ın ayarlarını incele

Helm chart'ı kurmadan önce hangi ayarların değiştirilebileceğini gör.

```bash
helm show values bitnami/wordpress > /tmp/wordpress-default-values.yaml
less /tmp/wordpress-default-values.yaml
```

Bu dosyada WordPress, MariaDB, Service ve persistence ayarları bulunur. `q` ile görüntüleyiciden çık.

## 3. Lab değerlerini kullanarak WordPress'i kur

Starter values dosyası WordPress Service'ini ClusterIP olarak bırakır. Böylece yeni bir host portu açılmaz; erişim için sonraki adımda kontrollü port-forward kullanılır.

```bash
kubectl create namespace wordpress-lab
helm install wordpress bitnami/wordpress \
  --namespace wordpress-lab \
  --values labs/lab-10-wordpress-ile-helm-operasyonlari/starter/values.yaml \
  --wait
helm list -n wordpress-lab
kubectl -n wordpress-lab get pods,service,pvc
```

Beklenen sonuç: `wordpress` release'i `deployed` görünür. WordPress ve MariaDB Pod'ları çalışır; MariaDB için PVC oluşur.

## 4. Uygulamayı yerel port-forward ile aç

Port-forward, yalnızca bu terminal açıkken bilgisayarındaki `8088` portunu Service'e bağlar. Kalıcı bir firewall veya Nginx değişikliği yapmaz.

```bash
kubectl -n wordpress-lab port-forward service/wordpress 8088:80
```

Yeni terminalde aşağıdaki adresi aç veya test et.

```bash
curl -I http://127.0.0.1:8088
```

Beklenen sonuç: `HTTP/1.1 200 OK` veya yönlendirme yanıtı görünür. Port-forward terminalini açık bırak; işin bitince `Ctrl+C` ile kapat.

## 5. Release değerini değiştirerek upgrade yap

Helm, release'e yeni revision ekler. Burada WordPress blog adını değiştiriyoruz.

```bash
helm upgrade wordpress bitnami/wordpress \
  --namespace wordpress-lab \
  --values labs/lab-10-wordpress-ile-helm-operasyonlari/starter/values.yaml \
  --set wordpressBlogName="Kubernetes Helm Lab" \
  --wait
helm history wordpress -n wordpress-lab
helm get values wordpress -n wordpress-lab
```

Beklenen sonuç: `helm history` içinde revision `1` ve `2` görünür. Not: komutta namespace her zaman `wordpress-lab` olmalıdır; yanlış namespace ile çalıştırma.

## 6. Önceki revision'a geri dön

```bash
helm rollback wordpress 1 --namespace wordpress-lab --wait
helm status wordpress -n wordpress-lab
```

Beklenen sonuç: release `deployed`, revision tekrar `1` olur.

## 7. Yalnızca geçici WordPress release'ini kaldır

```bash
helm uninstall wordpress --namespace wordpress-lab
kubectl delete namespace wordpress-lab
helm repo remove bitnami
```

Beklenen sonuç: WordPress kaynakları silinir, Bitnami repository listeden kalkar. Bu işlem ileride kurulacak monitoring platformuna dokunmaz.
