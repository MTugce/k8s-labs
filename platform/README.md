# Platform Hazırlığı: Kind Kümesini Kur

Bu bölüm lab değildir. Eğitmenle birlikte bir kez yapılır. Amaç, bütün labların kullanacağı üç node'lu Kind kümesini ve gerekli eklentileri hazırlamaktır.

## 1. Ön kontrol

Önce araçların hazır olduğunu doğrulayın. Çıktıda sürüm bilgisi görmelisiniz.

```bash
docker --version
kind version
kubectl version --client
helm version --short
```

## 2. Portları anlayın

Sunucunun `80` ve `443` portları Edge Nginx'e aittir; bu portlara dokunmayın. Kind yalnızca aşağıdaki boş portları kullanır:

| Port | Kullanım |
| --- | --- |
| `19001`, `19002`, `19003` | Sırasıyla app1, app2, app3 için Kind içindeki HTTP `:80` |
| `30086` | Service türleri NodePort testi |
| `30087` | Private uygulama NodePort testi |
| `30088` | Gateway API preview testi |
| `30089` | Kalıcı Grafana NodePort erişimi |

Aşağıdaki komut, bu portların boş olduğunu gösterir. Çıktı gelmemelidir.

```bash
sudo ss -ltnp '( sport = :19001 or sport = :19002 or sport = :19003 or sport = :30086 or sport = :30087 or sport = :30088 or sport = :30089 )'
```

Bir port doluysa servisi durdurmayın; eğitmene bildirin. `18081`, `18443`, `30080-30085` ve `30090` bu eğitim için kullanılmaz.

## 3. Static storage için host dizinini hazırlayın

Static storage labında kullanılacak HostPath PV'nin verisi bu dizinde kalır. Dizin Kind node'larına ayrıca bağlanacaktır.

```bash
sudo mkdir -p /opt/k8s-labs/static-pv
sudo chmod 0777 /opt/k8s-labs/static-pv
ls -ld /opt/k8s-labs/static-pv
```

Son komutta dizin adı görünmelidir.

## 4. Kind kümesini oluşturun

`platform/kind-cluster.yaml`, bir control-plane ve iki worker node tanımlar. Ayrıca `19001-19003` ile `30086-30089` port eşlemelerini içerir.

```bash
kind create cluster --name k8s-labs --config platform/kind-cluster.yaml
kubectl config use-context kind-k8s-labs
kubectl get nodes -o wide
```

Beklenen sonuç: üç node `Ready` durumundadır. Bir node `control-plane`, ikisi `worker` rolündedir.

## 5. Ingress controller kurun

Bu controller, dördüncü labda DNS adıyla gelen HTTP isteğini Service'e iletecektir.

```bash
kubectl apply -f https://github.com/kubernetes/ingress-nginx/raw/controller-v1.12.0/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=Ready pod \
  --selector=app.kubernetes.io/component=controller --timeout=180s
kubectl get pods -n ingress-nginx
```

Beklenen sonuç: `ingress-nginx-controller` Pod'u `Running` görünür.

## 6. Metrics Server kurun

HPA labında CPU kullanımını okuyabilmek için Metrics Server gerekir.

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.7.2/components.yaml
kubectl -n kube-system patch deployment metrics-server --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
kubectl wait -n kube-system --for=condition=Available deployment/metrics-server --timeout=180s
kubectl top nodes
```

İlk `kubectl top nodes` komutunda değerlerin gelmesi kısa sürebilir. Sonuçta her node için CPU ve memory sütunları görünmelidir.

## 7. Dynamic local storage kurun

Altıncı labda PVC'nin otomatik PV oluşturmasını görmek için local-path provisioner kullanılır.

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.36/deploy/local-path-storage.yaml
kubectl wait -n local-path-storage --for=condition=Available deployment/local-path-provisioner --timeout=180s
kubectl get storageclass
```

Beklenen sonuç: listede `local-path` StorageClass'ı görünür. Kurulum tamamlanmıştır; ilk laba geçebilirsiniz.
