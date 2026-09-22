# Kubernetes Labs: Başlangıçtan Orta Seviyeye

Bu depo, mevcut Azure öğrenci altyapısını değiştirmeden çalışan dokuz laboratuvarlık Kubernetes eğitim yoludur. Her konu kısa sunumla başlar ve hemen ardından aynı `devops-app` uygulaması üzerinde uygulanır.

## Sabit platform sözleşmesi

Azure öğrenci VM'lerinde Edge Nginx, Cloudflare DNS ve açık portlar zaten hazırdır. Bu depo onları değiştirmez.

```text
https://student01-app1.devopsatolyesi.com
       │ Edge Nginx :443 (TLS burada sonlanır)
       ▼
127.0.0.1:19001
       ▼
Kind control-plane :80
       ▼
NGINX Ingress veya Gateway API controller
       ▼
ClusterIP Service → devops-app Pod'ları
```

DNS otomasyonunun alan adı biçimi `student01-app1.devopsatolyesi.com` şeklindedir; `student01.app1...` kullanılmaz.

| Host portu | Sahibi | Bu depodaki kullanım |
| --- | --- | --- |
| `80`, `443` | Edge Nginx | Dokunulmaz |
| `18081`, `18443` | Eski/opsiyonel lablar | Kullanılmaz |
| `19001`, `19002`, `19003` | app1/app2/app3 slotları | Kind HTTP girişleri |
| `30080-30085` | NovaShop | Kullanılmaz |
| `30086-30089` | Kubernetes lab alanı | Doğrudan NodePort testleri |
| `30090` | Traefik/dashboard | Kullanılmaz |

`18443` bu başlangıç-orta seviye yolunda gerekli değildir: HTTPS Edge Nginx'te sonlanır. Cluster içi TLS, ileri seviye ek konu olarak ayrı tutulur.

## Başlangıç

```bash
git clone https://gitlab.com/devops-practitioner-labs/k8s-labs.git
cd k8s-labs
./platform/setup-kind-cluster.sh
```

Kurulum, çakışan bir host portu bulursa mevcut altyapıyı değiştirmeden durur.

Kind topolojisi, port sahipliği ve erişim akışı: [Kind Kurulumu ve Port Sözleşmesi](docs/kind-ve-port-sozlesmesi.md).

## Eğitim sırası

| Sıra | Uygulama | Sunum |
| --- | --- | --- |
| 1 | [Kind Kümeni Kur ve Kubectl ile Başla](labs/lab-01-kind-cluster-and-kubectl-basics/) | [01](slides/01-kind-kubectl.md) |
| 2 | [İlk Uygulaman: Pod, Deployment ve Service](labs/lab-02-first-app-pod-deployment-and-services/) | [02](slides/02-first-app.md) |
| 3 | [Kendi Docker İmajını Private Docker Hub'dan Çalıştır](labs/lab-03-private-dockerhub-image-configmap-secret/) | [03](slides/03-private-image.md) |
| 4 | [Uygulamanı NGINX Ingress ile İnternete Aç](labs/lab-04-nginx-ingress-routing/) | [04](slides/04-ingress.md) |
| 5 | [Ingress Kurallarını Gateway API'ye Taşı](labs/lab-05-ingress-to-gateway-api/) | [05](slides/05-gateway-api.md) |
| 6 | [Veriyi Kaybetme: PV, PVC, Static ve Dynamic Storage](labs/lab-06-static-and-dynamic-storage/) | [06](slides/06-storage.md) |
| 7 | [Paylaşımlı Depolama ve StatefulSet ile MySQL](labs/lab-07-nfs-storage-and-statefulset/) | [07](slides/07-statefulset.md) |
| 8 | [Her Node'da Ajan Çalıştır ve Uygulamanı Otomatik Ölçekle](labs/lab-08-daemonset-and-hpa-scaling/) | [08](slides/08-hpa.md) |
| 9 | [Sürümü Güvenle Yayınla: Recreate, Rolling, Blue-Green, Canary](labs/lab-09-deployment-strategies/) | [09](slides/09-strategies.md) |

Lab metadatası ve sıra için tek kaynak [curriculum.yaml](curriculum.yaml) dosyasıdır.
Konu anlatımı → lab sırası için [Eğitim Akışı](docs/egitim-akisi.md) dosyasını kullanın.

## Hızlı başvuru

Lab sırasında kullanılacak Kind ve kubectl komutları ayrı tutulur: [Kubectl ve Kind Hızlı Başvuru](cheat-sheets/kubectl-ve-kind-hizli-basvuru.md).

## Ortak imaj kuralı

Her öğrenci kendi private Docker Hub repository'sini kullanır. Varsayılan ad:

```bash
export DOCKERHUB_USER="kendi_kullanici_adin"
export IMAGE_REPOSITORY="devops-app"
export IMAGE_TAG="1.0"
export IMAGE="docker.io/${DOCKERHUB_USER}/${IMAGE_REPOSITORY}:${IMAGE_TAG}"
```

Örnek: `docker.io/ayse/devops-app:1.0`. Aynı hesapta ikinci uygulama gerekiyorsa yeni repository adı kullanılır; farklı uygulamalar tek repository içinde karışık tag'lerle tutulmaz.

## Erişim kuralları

- Ingress/Gateway testinde DNS adı veya açıkça verilmiş `Host` header kullanılır.
- Host'suz fallback Ingress/HTTPRoute oluşturulmaz; başka eğitim uygulamalarının trafiği yanlış yakalanmaz.
- Doğrudan IP/port testi NodePort Service ile yapılır: örneğin `http://SUNUCU_IP:30086`.
- Gerçek Secret, Docker Hub tokeni veya yerel `*.local.yaml` dosyası Git'e eklenmez.
