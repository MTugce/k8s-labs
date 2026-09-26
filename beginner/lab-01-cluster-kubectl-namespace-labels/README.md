# Kind Cluster, kubectl, Context, Kubeconfig, Namespace ve Label

> **Seviye:** Başlangıç
> **Tahmini süre:** 75–90 dakika
> **Eğitim durumu:** Zorunlu

## Amaç

Bu labda Kind cluster yaşam döngüsünü ve `kubectl` bağlantı modelini inceleyecek, geçici bir `k8s-test` cluster'ı oluşturarak iki cluster arasında context değiştirecek ve kubeconfig kurtarma yöntemlerini uygulayacaksınız. Ardından ana `k8s-labs` cluster'ında node, API kaynağı, namespace, Pod, label ve selector çalışmalarını tamamlayacaksınız.

Lab boyunca mevcut `k8s-labs` cluster'ı silinmez veya yeniden oluşturulmaz. Yalnızca bu çalışma için oluşturulan `k8s-test` cluster'ı labın sonunda silinir.

## Kullanılan Kavramlar

| Kavram | Açıklama |
|---|---|
| **Cluster** | Kubernetes API sunucusu, control-plane bileşenleri ve worker node'lardan oluşan çalışma ortamıdır. |
| **Kubeconfig** | Cluster adreslerini, kullanıcı kimlik bilgilerini, context tanımlarını ve aktif context'i tutar. |
| **Context** | Bir cluster, bir kullanıcı ve isteğe bağlı varsayılan namespace birleşimidir. |
| **Current context** | `kubectl` komutlarının varsayılan olarak hedeflediği context'tir. |
| **Namespace** | Kubernetes kaynaklarını mantıksal olarak ayırır. |
| **Label** | Kubernetes nesnelerine anahtar-değer biçiminde kimlik ekler. |
| **Selector** | Belirli label'lara sahip nesneleri seçer. |

Bir context'in çalışma modeli şöyledir:

```text
kubectl
  │
  └── current-context
        ├── cluster   → API sunucusunun adresi ve CA bilgisi
        ├── user      → Kimlik doğrulama bilgisi
        └── namespace → Belirtilmezse default
```

Yanlış context seçiliyken çalışan geçerli bir `kubectl apply` komutu, doğru manifesti yanlış cluster'a gönderebilir. Değişiklik yapan komutlardan önce aktif context ve namespace kontrol edilmelidir.

## Çalışma Dizini

```bash
cd ~/k8s-labs/beginner/lab-01-cluster-kubectl-namespace-labels
```

## 1. Kind ve Kubeconfig Durumunu İnceleme

Docker üzerinde çalışan Kind cluster'larını listeleyin:

```bash
kind get clusters
```

Beklenen sonuçta ana cluster görünmelidir:

```text
k8s-labs
```

`kubectl` tarafından bilinen cluster, kullanıcı ve context kayıtlarını ayrı ayrı görüntüleyin:

```bash
kubectl config get-clusters
kubectl config get-users
kubectl config get-contexts
kubectl config current-context
```

`kubectl config get-clusters` kubeconfig kayıtlarını, `kind get clusters` ise Docker üzerinde gerçekten bulunan Kind cluster'larını listeler. Bu iki liste aynı kavramı ölçmez; silinmiş bir cluster'a ait eski kubeconfig kaydı listede kalabilir.

Varsayılan kubeconfig konumunu görüntüleyin:

```bash
printf 'Kullanılan kubeconfig: %s\n' "${KUBECONFIG:-$HOME/.kube/config}"
```

`KUBECONFIG` tanımlı değilse `kubectl`, varsayılan olarak `$HOME/.kube/config` dosyasını kullanır. `KUBECONFIG` birden fazla dosya içeriyorsa Linux ve macOS üzerinde yollar `:` karakteriyle ayrılır ve `kubectl` bu dosyaları birleştirerek okur.

Aktif context'e ait etkili ayarları güvenli görünümle inceleyin:

```bash
kubectl config view --minify
```

`--minify` yalnızca aktif context ile ilgili kayıtları gösterir. Kubeconfig dosyaları client certificate, token veya harici kimlik doğrulama komutları içerebildiği için güvenilmeyen kubeconfig dosyalarını doğrudan kullanmayın ve `kubectl config view --raw` çıktısını paylaşmayın.

Ana cluster'ı açıkça seçip bağlantıyı doğrulayın:

```bash
kubectl config use-context kind-k8s-labs
kubectl cluster-info
kubectl get nodes
```

Beklenen sonuç: Aktif context `kind-k8s-labs` olur ve üç node `Ready` görünür.

## 2. Geçici `k8s-test` Cluster'ını Oluşturma

Bu çalışma için port eşlemesi veya ek storage mount'u olmayan, tek node'lu bağımsız bir Kind cluster oluşturun:

```bash
kind create cluster --name k8s-test --wait 120s
```

Cluster zaten daha önce oluşturulduysa aynı komutu yeniden çalıştırmayın. Mevcut cluster'ları ve yeni kubeconfig context'ini doğrulayın:

```bash
kind get clusters
kubectl config get-contexts
```

Beklenen sonuç:

```text
Kind cluster adı     kubectl context adı
k8s-labs             kind-k8s-labs
k8s-test             kind-k8s-test
```

Kind cluster adı ile kubectl context adının aynı olmadığına dikkat edin. Kind, oluşturduğu context adının başına `kind-` ekler.

Context'i değiştirmeden iki API sunucusunu ayrı ayrı kontrol edin:

```bash
kubectl cluster-info --context kind-k8s-labs
kubectl cluster-info --context kind-k8s-test
```

## 3. Cluster'lar Arasında Context Değiştirme

Geçici cluster'a geçin ve aktif context'i doğrulayın:

```bash
kubectl config use-context kind-k8s-test
kubectl config current-context
kubectl get nodes -o wide
```

Beklenen sonuç: `kind-k8s-test` context'i ve tek bir control-plane node görünür.

Geçici cluster'da bir Pod çalıştırın:

```bash
kubectl run context-demo \
  --image=nginx:1.27-alpine \
  --restart=Never

kubectl wait \
  --for=condition=Ready \
  pod/context-demo \
  --timeout=90s

kubectl get pod context-demo -o wide
```

Ana cluster'a dönün:

```bash
kubectl config use-context kind-k8s-labs
kubectl config current-context
kubectl get nodes
```

`context-demo` Pod'unu aktif context'te arayın:

```bash
kubectl get pod context-demo
```

Beklenen sonuç: Ana cluster'da bu Pod oluşturulmadığı için `NotFound` hatası alınır. Aynı kaynağı aktif context'i değiştirmeden `--context` ile geçici cluster'da görüntüleyin:

```bash
kubectl --context kind-k8s-test get pod context-demo
```

`--context`, yalnızca çalıştırılan komut için hedef cluster'ı değiştirir; kubeconfig içindeki `current-context` değerini değiştirmez:

```bash
kubectl config current-context
```

Beklenen sonuç halen `kind-k8s-labs` olmalıdır.

## 4. Kind Kubeconfig Dosyalarını Yeniden Üretme

Kubeconfig kaybını ana dosyayı silmeden, bu laba ait `work/` dizininde güvenli şekilde simüle edin:

```bash
mkdir -p work
umask 077

kind get kubeconfig --name k8s-labs \
  > work/k8s-labs-recovered.yaml

kind get kubeconfig --name k8s-test \
  > work/k8s-test-recovered.yaml
```

Kind, çalışan cluster'lardan host tarafından kullanılabilecek kubeconfig çıktılarını yeniden üretir. Kurtarılan her dosyayı ana kubeconfig'ten bağımsız doğrulayın:

```bash
kubectl --kubeconfig work/k8s-labs-recovered.yaml \
  config current-context

kubectl --kubeconfig work/k8s-labs-recovered.yaml \
  get nodes

kubectl --kubeconfig work/k8s-test-recovered.yaml \
  get nodes
```

İki kurtarma dosyasını tek bir taşınabilir kubeconfig içinde birleştirin:

```bash
KUBECONFIG="$PWD/work/k8s-labs-recovered.yaml:$PWD/work/k8s-test-recovered.yaml" \
  kubectl config view --flatten \
  > work/two-clusters.yaml
```

Birleştirilmiş dosyadaki context'leri görüntüleyin:

```bash
kubectl --kubeconfig work/two-clusters.yaml config get-contexts
```

Ana kubeconfig dosyasını değiştirmeden, yalnızca bu dosya içindeki aktif context'i değiştirin:

```bash
kubectl --kubeconfig work/two-clusters.yaml \
  config use-context kind-k8s-test

kubectl --kubeconfig work/two-clusters.yaml \
  get nodes

kubectl --kubeconfig work/two-clusters.yaml \
  config use-context kind-k8s-labs
```

Gerçek `$HOME/.kube/config` dosyası kaybolduğunda izlenecek güvenli sıra şöyledir:

1. `kind get clusters` ile Docker üzerindeki cluster'ın çalıştığını doğrulayın.
2. `kind get kubeconfig --name CLUSTER_ADI` çıktısını yeni bir dosyaya yazın.
3. `kubectl --kubeconfig DOSYA get nodes` ile dosyayı test edin.
4. Birden fazla cluster varsa dosyaları `KUBECONFIG` ile birleştirip `--flatten` çıktısı üretin.
5. Yalnızca doğrulamadan sonra kurtarılan dosyayı varsayılan konuma yerleştirin.

Varsayılan kubeconfig gerçekten mevcut değilse doğrulanan dosya şu şekilde yerleştirilebilir:

```bash
install -d -m 700 "$HOME/.kube"
install -m 600 work/two-clusters.yaml "$HOME/.kube/config"
```

Bu iki komutu mevcut ve çalışan bir `$HOME/.kube/config` dosyasının üzerine uygulamayın. Mevcut dosyaya yeni kayıt eklemek gerekiyorsa önce yedek alın ve `KUBECONFIG` ile birleştirilmiş çıktıyı ayrı bir dosyada doğrulayın.

## 5. Kind Control-plane İçindeki Kubeconfig'i İnceleme

Kind node'ları Docker container'ları olarak çalışır. Ana cluster'ın control-plane container'ını bulun:

```bash
docker ps \
  --filter name=k8s-labs-control-plane \
  --format 'table {{.Names}}\t{{.Status}}'
```

Control-plane container'ına girin:

```bash
docker exec -it k8s-labs-control-plane sh
```

Container içindeyken kubeconfig dosyasını ve güvenli alanlarını inceleyin:

```bash
ls -l /etc/kubernetes/admin.conf
grep -E 'server:|current-context:' /etc/kubernetes/admin.conf
exit
```

`/etc/kubernetes/admin.conf`, control-plane tarafından kullanılan yönetici kubeconfig'idir. İçindeki API adresi container ağına göre hazırlanmış olabilir; dosyayı doğrudan `$HOME/.kube/config` üzerine kopyalamayın.

Dosyanın bir kopyasını yalnızca incelemek için lab dizinine alın:

```bash
docker cp \
  k8s-labs-control-plane:/etc/kubernetes/admin.conf \
  work/k8s-labs-admin-internal.conf

kubectl --kubeconfig work/k8s-labs-admin-internal.conf \
  config view --minify
```

Host üzerinde kullanılabilir kubeconfig kurtarmanın tercih edilen yöntemi şudur:

```bash
kind get kubeconfig --name k8s-labs \
  > work/k8s-labs-host.yaml

kubectl --kubeconfig work/k8s-labs-host.yaml \
  get nodes
```

`kind get kubeconfig`, cluster container'ından gerekli bilgileri alır ve API adresini host tarafından erişilebilecek endpoint'e göre düzenler. `admin.conf` ise cluster içindeki kaynağın nerede bulunduğunu anlamak ve ileri seviye arıza incelemesi yapmak için kullanılır.

## 6. Ana Cluster'a Dönme

Geçici cluster'ı labın sonuna kadar çalışır durumda bırakın. Uygulama çalışmalarına başlamadan önce ana cluster'ı seçin:

```bash
kind get clusters
kubectl config use-context kind-k8s-labs
kubectl config current-context
kubectl get nodes
```

Beklenen sonuç:

- `kind get clusters` çıktısında `k8s-labs` ve `k8s-test` bulunur.
- Aktif context `kind-k8s-labs` olur.
- Ana cluster'ın üç node'u `Ready` durumundadır.

Ana `k8s-labs` cluster'ını silmeyin veya yeniden oluşturmayın. Bu cluster sonraki lablarda kullanılacaktır.

## 7. Node'ları ve Sistem Pod'larını İnceleme

Ana cluster'daki node'ları ve Kubernetes sistem bileşenlerini listeleyin:

```bash
kubectl get nodes -o wide
kubectl get pods -n kube-system
```

Beklenen sonuç: Bir control-plane ve iki worker node `Ready` durumundadır. `kube-system` namespace'inde DNS ve ağ bileşenleri çalışır.

Bir worker node'un ayrıntılarını inceleyin:

```bash
kubectl describe node k8s-labs-worker
```

Çıktıdaki `Labels`, `Taints`, `Conditions` ve `Allocated resources` bölümlerini bulun.

## 8. Kubernetes API Kaynaklarını Keşfetme

Cluster'ın desteklediği kaynak türlerini listeleyin:

```bash
kubectl api-resources
```

Pod ve Deployment alanlarının açıklamalarını görüntüleyin:

```bash
kubectl explain pod
kubectl explain deployment.spec.replicas
```

Bu komutlar açıklamaları doğrudan aktif cluster'ın Kubernetes API şemasından alır.

## 9. Namespace ve Etiketli Pod'ları Oluşturma

Aktif context'i son kez doğrulayın:

```bash
kubectl config current-context
```

Çıktı `kind-k8s-labs` değilse devam etmeden önce düzeltin:

```bash
kubectl config use-context kind-k8s-labs
```

Hazır manifesti uygulayın:

```bash
kubectl apply -f starter/labeled-pods.yaml
```

Namespace'i ve Pod'ları doğrulayın:

```bash
kubectl get namespace cluster-basics
kubectl get pods -n cluster-basics --show-labels
kubectl wait \
  -n cluster-basics \
  --for=condition=Ready \
  pod/frontend pod/backend \
  --timeout=90s
```

Beklenen sonuç: `frontend` ve `backend` Pod'ları `Running` durumuna gelir ve label'ları görünür.

## 10. Selector ile Doğru Pod'u Bulma

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
kubectl get pods \
  -n cluster-basics \
  -l 'environment=training,tier=backend'
```

Beklenen sonuç: İlk komut `frontend`, diğer iki komut `backend` Pod'unu gösterir.

## 11. Label Ekleme ve Değiştirme

Frontend Pod'una yeni bir label ekleyin:

```bash
kubectl label pod frontend \
  -n cluster-basics \
  owner=platform

kubectl get pod frontend \
  -n cluster-basics \
  --show-labels
```

Label değerini değiştirin:

```bash
kubectl label pod frontend \
  -n cluster-basics \
  owner=operations \
  --overwrite

kubectl get pod frontend \
  -n cluster-basics \
  -L owner
```

Beklenen sonuç: `OWNER` sütununda `operations` görünür.

## 12. Olayları İnceleme

Namespace içindeki son olayları zaman sırasıyla görüntüleyin:

```bash
kubectl get events \
  -n cluster-basics \
  --sort-by=.metadata.creationTimestamp
```

Pod'ların oluşturulması, image'ların çekilmesi ve container'ların başlamasıyla ilgili olaylar görünür.

## Ek Çalışma

Yalnızca `environment=training` label'ına sahip Pod adlarını JSONPath ile yazdırın:

```bash
kubectl get pods \
  -n cluster-basics \
  -l environment=training \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
```

## Temizlik

Aktif context'i kontrol edin ve yalnızca bu laba ait namespace'i silin:

```bash
kubectl config use-context kind-k8s-labs
kubectl delete namespace cluster-basics
```

Kubeconfig kopyaları kimlik doğrulama verisi içerdiğinden lab için oluşturulan dosyaları temizleyin:

```bash
rm -f \
  work/k8s-labs-recovered.yaml \
  work/k8s-test-recovered.yaml \
  work/two-clusters.yaml \
  work/k8s-labs-admin-internal.conf \
  work/k8s-labs-host.yaml
```

Labın son cluster işlemi olarak yalnızca geçici `k8s-test` cluster'ını silin:

```bash
kind delete cluster --name k8s-test
```

Son durumu doğrulayın:

```bash
kind get clusters
kubectl config current-context
kubectl get namespace cluster-basics
```

Beklenen sonuç: Yalnızca `k8s-labs` Kind cluster'ı kalır, aktif context `kind-k8s-labs` olur ve `cluster-basics` namespace'i bulunamaz. Ana cluster silinmez.

## Başarı Kriterleri

- Cluster, user, context ve current-context ilişkisini açıklayabiliyorsunuz.
- `k8s-test` cluster'ını oluşturup iki cluster arasında context değiştirdiniz.
- `--context` ile aktif context'i kalıcı olarak değiştirmeden komut çalıştırdınız.
- Kind kubeconfig dosyalarını yeniden üretip ayrı dosyada doğruladınız.
- Control-plane içindeki `/etc/kubernetes/admin.conf` dosyasını güvenli biçimde incelediniz.
- Yalnızca `k8s-test` cluster'ını sildiniz ve `k8s-labs` cluster'ına geri döndünüz.
- Ana cluster'daki node ve sistem Pod'larını incelediniz.
- Namespace içindeki Pod'ları label selector ile seçtiniz.
- Bir label değerini ekleyip değiştirdiniz.
