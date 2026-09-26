# Kind Cluster Kurulumu

Bu adım tüm lablardan önce bir kez yapılır.

## 1. Gerekli araçları kur ve kontrol et

Gerekli tüm araçları (Docker, Kind, kubectl, helm) ve disk dizinini tek komutla otomatik ve hatasız kurmak için:

```bash
cd ~/k8s-labs
./platform/install-prerequisites.sh
```

*(Eğer araçlar zaten kuruluysa betik hata vermeden mevcut sürümleri gösterir ve eksikleri tamamlar).*

Manuel kontrol etmek isterseniz:

```bash
docker --version
kind version
kubectl version --client
helm version --short
```

Her komutta sürüm bilgisi görmelisin.

## 2. Static disk dizinini hazırla

Beşinci labdaki static PV bu dizini kullanır. Kind cluster oluşturulurken bu dizin node'lara bağlanır.

```bash
sudo mkdir -p /opt/k8s-labs/static-pv
sudo chmod 0777 /opt/k8s-labs/static-pv
```

## 3. Kind cluster'ı oluştur

Bu komut bir control-plane ve iki worker node oluşturur. `19001-19003` ile `30086-30089` port eşlemeleri `platform/kind-cluster.yaml` içindedir.

```bash
cd ~/k8s-labs
kind create cluster --name k8s-labs --config platform/kind-cluster.yaml
```

## 4. Cluster'a bağlan ve kontrol et

`kubectl` komutlarının yeni cluster'a gitmesi için context seçilir.

```bash
kubectl config use-context kind-k8s-labs
kubectl get nodes -o wide
```

Beklenen sonuç: üç node `Ready` görünür. Bundan sonra Lab 1'e geçebilirsin.
