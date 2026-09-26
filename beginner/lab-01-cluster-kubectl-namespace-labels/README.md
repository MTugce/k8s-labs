# Cluster'ı Tanı: kubectl, Namespace, Label ve Selector

> **Seviye:** Başlangıç
> **Tahmini süre:** 35–45 dakika
> **Eğitim durumu:** Zorunlu

## Amaç

Bu labda Kubernetes cluster'ına bağlanacak, node'ları ve API kaynaklarını inceleyecek, namespace ile kaynakları ayıracak ve label/selector kullanarak doğru Pod'ları bulacaksınız.

## Kullanılan kavramlar

- **Context:** `kubectl` komutlarının hangi cluster ve kullanıcıyla çalışacağını belirler.
- **Namespace:** Kaynakları mantıksal olarak ayırır.
- **Label:** Kubernetes nesnelerine anahtar-değer biçiminde kimlik ekler.
- **Selector:** Belirli label'lara sahip nesneleri seçer.

## Çalışma dizini

```bash
cd ~/k8s-labs/beginner/lab-01-cluster-kubectl-namespace-labels
```

## 1. Aktif cluster bağlantısını kontrol et

Önce aktif context'i ve cluster bilgisini görüntüleyin:

```bash
kubectl config current-context
kubectl cluster-info
```

Beklenen sonuç: Context olarak `kind-k8s-labs` ve erişilebilir bir Kubernetes API adresi görünür.

Farklı bir context görünüyorsa doğru context'i seçin:

```bash
kubectl config use-context kind-k8s-labs
```

## 2. Node'ları ve sistem Pod'larını incele

```bash
kubectl get nodes -o wide
kubectl get pods -n kube-system
```

Beklenen sonuç: Bir control-plane ve iki worker node `Ready` durumundadır. `kube-system` namespace'inde DNS ve ağ bileşenleri çalışır.

Bir node'un ayrıntılarını inceleyin:

```bash
kubectl describe node k8s-labs-worker
```

`Labels`, `Taints`, `Conditions` ve `Allocated resources` bölümlerini bulun.

## 3. Kubernetes API kaynaklarını keşfet

Cluster'ın desteklediği kaynak türlerini listeleyin:

```bash
kubectl api-resources
```

Pod ve Deployment alanlarının açıklamalarını görüntüleyin:

```bash
kubectl explain pod
kubectl explain deployment.spec.replicas
```

Bu komutlar internet bağlantısı kullanmaz; açıklamayı doğrudan Kubernetes API şemasından alır.

## 4. Namespace ve etiketli Pod'ları oluştur

Hazır manifesti uygulayın:

```bash
kubectl apply -f starter/labeled-pods.yaml
```

Namespace'i ve Pod'ları doğrulayın:

```bash
kubectl get namespace cluster-basics
kubectl get pods -n cluster-basics --show-labels
kubectl wait -n cluster-basics --for=condition=Ready pod/frontend pod/backend --timeout=90s
```

Beklenen sonuç: `frontend` ve `backend` Pod'ları `Running` durumuna gelir ve label'ları görünür.

## 5. Selector ile doğru Pod'u bul

Yalnızca frontend Pod'unu seçin:

```bash
kubectl get pods -n cluster-basics -l tier=frontend
```

Yalnızca `app=api` label'ına sahip Pod'u seçin:

```bash
kubectl get pods -n cluster-basics -l app=api
```

Birden fazla koşulu birlikte kullanın:

```bash
kubectl get pods -n cluster-basics -l 'environment=training,tier=backend'
```

Beklenen sonuç: İlk komut `frontend`, diğer iki komut `backend` Pod'unu gösterir.

## 6. Label ekle ve değiştir

Frontend Pod'una yeni bir label ekleyin:

```bash
kubectl label pod frontend -n cluster-basics owner=student
kubectl get pod frontend -n cluster-basics --show-labels
```

Label değerini değiştirin:

```bash
kubectl label pod frontend -n cluster-basics owner=admin --overwrite
kubectl get pod frontend -n cluster-basics -L owner
```

Beklenen sonuç: `OWNER` sütununda `admin` görünür.

## 7. Olayları incele

Namespace içindeki son olayları zaman sırasıyla görüntüleyin:

```bash
kubectl get events -n cluster-basics --sort-by=.metadata.creationTimestamp
```

Pod'ların oluşturulması, imajların çekilmesi ve container'ların başlamasıyla ilgili olaylar görünür.

## Başarı kriterleri

- Üç node'u ve sistem Pod'larını listeleyebiliyorsunuz.
- `kubectl explain` ile bir API alanını inceleyebiliyorsunuz.
- Namespace içindeki Pod'ları label selector ile ayrı ayrı seçebiliyorsunuz.
- Bir label'ı ekleyip değiştirebiliyorsunuz.

## Hızlı öğrenci ek görevi

Yalnızca `environment=training` label'ına sahip Pod adlarını JSONPath ile yazdırın:

```bash
kubectl get pods -n cluster-basics -l environment=training \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
```

## Temizlik

```bash
kubectl delete namespace cluster-basics
```
