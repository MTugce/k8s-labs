# Kubectl ve Kind Hızlı Başvuru

Bu sayfa labdaki komutların kısa anlamını hatırlatır. `NAME`, `NAME_SPACE`, `IMAGE` ve `POD_ADI` alanlarını kendi değerlerinle değiştir.

## Cluster

### Cluster listesini gör

Bilgisayarında Kind ile oluşturulmuş cluster adlarını listeler.

```bash
kind get clusters
```

### Lab cluster'ını oluştur

Bu repodaki port ve disk ayarlarıyla `k8s-labs` adlı cluster oluşturur. Bu komut cluster henüz yoksa bir kez çalıştırılır.

```bash
kind create cluster --name k8s-labs --config ~/k8s-labs/platform/kind-cluster.yaml
```

### Aktif Kubernetes hedefini seç

Sonraki `kubectl` komutlarının `k8s-labs` cluster'ına gitmesini sağlar.

```bash
kubectl config use-context kind-k8s-labs
```

### Node'ları kontrol et

Control-plane ve worker node'ların hazır olup olmadığını gösterir.

```bash
kubectl get nodes -o wide
```

## Namespace

### Yeni çalışma alanı oluştur

Kaynakları birbirinden ayırmak için namespace oluşturur.

```bash
kubectl create namespace NAME_SPACE
```

### Namespace içindeki kaynakları listele

Pod, Service, Deployment gibi temel kaynakları birlikte gösterir.

```bash
kubectl get all -n NAME_SPACE
```

## Pod

### Tek Pod oluştur

YAML yazmadan hızlı bir test Pod'u oluşturur.

```bash
kubectl run NAME --image=IMAGE
```

### Pod ayrıntısını incele

Image çekme, başlatma ve hata olaylarını görürsün.

```bash
kubectl describe pod POD_ADI -n NAME_SPACE
```

### Pod loglarını gör

Container'ın standart çıktısını gösterir.

```bash
kubectl logs POD_ADI -n NAME_SPACE
```

### Pod içine komut gönder

Çalışan container içinde örneğin `sh` başlatır.

```bash
kubectl exec -it POD_ADI -n NAME_SPACE -- sh
```

## Deployment

### Deployment oluştur

Kubernetes'in belirli sayıda Pod'u sürekli çalıştırmasını sağlar.

```bash
kubectl create deployment NAME --image=IMAGE -n NAME_SPACE
```

### Pod sayısını değiştir

Deployment'ın istediği replica sayısını artırır veya azaltır.

```bash
kubectl scale deployment/NAME --replicas=3 -n NAME_SPACE
```

### Deployment image'ini değiştir

Yeni image sürümüyle rollout başlatır.

```bash
kubectl set image deployment/NAME CONTAINER=IMAGE -n NAME_SPACE
```

### Rollout tamamlanana kadar bekle

Yeni Pod'ların hazır olup olmadığını takip eder.

```bash
kubectl rollout status deployment/NAME -n NAME_SPACE
```

### Önceki sürüme dön

Son rollout'u geri alır.

```bash
kubectl rollout undo deployment/NAME -n NAME_SPACE
```

## Service ve erişim

### Deployment'ı Service yap

Pod'lara sabit DNS adıyla erişmek için ClusterIP Service oluşturur.

```bash
kubectl expose deployment NAME --name=NAME-svc --port=80 -n NAME_SPACE
```

### Cluster içinden HTTP isteği at

Geçici curl Pod'u ile Service DNS adını test eder; iş bitince Pod silinir.

```bash
kubectl -n NAME_SPACE run curl --rm -it --restart=Never --image=curlimages/curl:8.12.1 -- curl -s SERVICE/healthz
```

### NodePort Service'i dışarıdan test et

Sunucunun IP adresi ve NodePort üzerinden uygulamaya ulaşır.

```bash
curl http://SUNUCU_IP:30086
```

## Storage

### PVC durumunu gör

Uygulamanın istediği diskin bağlı olup olmadığını gösterir.

```bash
kubectl get pvc -n NAME_SPACE
```

### Cluster disklerini gör

Static veya dynamic oluşan PersistentVolume kaynaklarını listeler.

```bash
kubectl get pv
```

## HPA ve metrik

### Anlık CPU ve memory kullanımını gör

Metrics Server'ın node veya Pod verisi üretip üretmediğini kontrol eder.

```bash
kubectl top pods -n NAME_SPACE
```

### HPA ile Pod değişimini izle

HPA replica sayısı ve Pod sayısı değiştikçe ekrana yeni satır basar. `Ctrl+C` ile durur.

```bash
kubectl get hpa,pods -n NAME_SPACE -w
```

## Helm

### Chart repository ekle

Helm'in chart indireceği kaynağı yerel listeye ekler.

```bash
helm repo add NAME URL
```

### Repository içindeki chart'ı ara

Kurmak istediğin chart'ın adını ve sürümünü bulur.

```bash
helm search repo KEYWORD
```

### Release'i kur veya güncelle

Release yoksa kurar; varsa values dosyasındaki yeni ayarlarla günceller.

```bash
helm upgrade --install RELEASE REPOSITORY/CHART -n NAME_SPACE -f values.yaml
```

### Release geçmişini gör

Install ve upgrade revision'larını listeler.

```bash
helm history RELEASE -n NAME_SPACE
```

### Belirli revision'a geri dön

Seçtiğin revision'ın değerleriyle release'i yeniden uygular.

```bash
helm rollback RELEASE REVISION -n NAME_SPACE
```

## RBAC

### Bir kimliğin işlem iznini test et

ServiceAccount'ın verilen namespace'te belirtilen işlemi yapıp yapamayacağını söyler.

```bash
kubectl auth can-i list pods --as=system:serviceaccount:NAME_SPACE:SERVICE_ACCOUNT -n NAME_SPACE
```
