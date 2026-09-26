# Kubernetes Labs

Bu laboratuvar serisi; temel Kubernetes nesnelerinden (Pod, Deployment, Service) başlayarak ileri seviye ağ yönetimi (Ingress, Gateway API), kalıcı depolama (PV/PVC, RWX NFS, StatefulSet), otomatik ölçekleme (HPA, DaemonSet), dağıtım stratejileri (Canary, Blue-Green), paket yönetimi (Helm) ve küme izlemeye (Prometheus, Grafana, Headlamp) kadar uçtan uca pratik yapmanızı sağlar.

> [!IMPORTANT]
> Bu laboratuvarların tamamı **Kind (Kubernetes in Docker)** kümesine tam uyumlu olarak tasarlanmıştır. Lablarda kullanılan ingress, servis portları ve kalıcı disk bağlama noktaları önceden belirlenmiş mimariye göre yapılandırılmıştır.

---

## 1. Sistem Gereksinimleri ve Ön Kontrol

Laboratuvarları çalıştırabilmek için sisteminizde (Ubuntu 20.04/22.04/24.04 önerilir) aşağıdaki 4 temel aracın kurulu olması gerekir:

1. **Docker:** Konteyner motoru ve Kind node'larının üzerinde çalışacağı ortam.
2. **Kind:** Docker konteynerleri içinde çok düğümlü (multi-node) yerel Kubernetes kümesi çalıştıran araç.
3. **kubectl:** Kubernetes API sunucusu ile iletişim kuran resmi komut satırı aracı.
4. **Helm:** Kubernetes için paket yöneticisi (WordPress, Traefik, Prometheus, Headlamp kurulumları için).

Sisteminizde bu araçların kurulu olup olmadığını kontrol etmek için aşağıdaki komutları çalıştırın:

```bash
docker --version
kind version
kubectl version --client
helm version --short
```

Her komutun çıktısında geçerli bir sürüm numarası görmelisiniz. Eğer araçlardan biri veya birkaçı eksikse, aşağıdaki **Otomatik Kurulum (Önerilen)** veya **Manuel Kurulum** adımlarını uygulayın.

---

## 2. Altyapı Kurulumu

### Seçenek A: Otomatik Kurulum (Önerilen)

Tüm araçları, Docker izinlerini ve kalıcı disk dizinlerini tek komutla, hata vermeden (idempotent mantığıyla) kurmak için repo içindeki hazır kurulum betiğini çalıştırabilirsiniz:

```bash
cd ~/k8s-labs
chmod +x install-prerequisites.sh
./install-prerequisites.sh
```

*Bu betik: Sistemde zaten kurulu olan araçları tespit ederek atlar, yalnızca eksik olanları resmi depolardan en güncel sürümleriyle kurar ve disk izinlerini ayarlar.*

---

### Seçenek B: Adım Adım Manuel Kurulum (Ubuntu)

Eğer her bileşeni adım adım elle kurarak öğrenmek isterseniz aşağıdaki talimatları izleyin:

#### 1. Temel Sistem Paketleri
```bash
sudo apt-get update -y
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release git conntrack jq
```

#### 2. Docker CE Kurulumu
Docker, Kind'in çalışması için zorunlu konteyner motorudur.
```bash
# Docker resmi GPG anahtarını ve reposunu ekle
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Docker'ı kur ve servisi başlat
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker

# Mevcut kullanıcınızı docker grubuna ekleyin (sudo olmadan docker çalıştırabilmek için)
sudo usermod -aG docker "$USER"
newgrp docker 2>/dev/null || true
```

#### 3. kubectl Kurulumu
`kubectl`, küme yönetiminde Pod, Deployment, Service gibi nesneleri oluşturup yönettiğimiz ana komut satırı aracıdır.
```bash
K8S_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
ARCH=$(dpkg --print-architecture)
curl -sLO "https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/${ARCH}/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm -f kubectl
```

#### 4. Kind Kurulumu
Kind, her bir Kubernetes node'unu bağımsız bir Docker konteyneri olarak ayağa kaldıran hafif bir araçtır.
```bash
KIND_VERSION="v0.27.0"
ARCH=$(dpkg --print-architecture)
curl -sLo ./kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-${ARCH}"
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind
```

#### 5. Helm Kurulumu
Helm, Kubernetes uygulamalarını Chart adı verilen şablon paketler halinde kurmayı ve yönetmeyi sağlar.
```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

#### 6. Static PV Dizinini Hazırla
Lab 05'te kullanılacak statik PersistentVolume'un host üzerinde yazabilmesi için bu dizin gereklidir:
```bash
sudo mkdir -p /opt/k8s-labs/static-pv
sudo chmod 0777 /opt/k8s-labs/static-pv
```

---

## 3. Kind Cluster Yapılandırması (`kind-cluster.yaml`)

Laboratuvarların sorunsuz çalışabilmesi için Kind kümesi özel bir ağ ve disk sözleşmesiyle yapılandırılmıştır. Dosya içeriği:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: k8s-labs
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      # Ingress & Gateway API HTTP slotları (Host 19001 -> Kind :80)
      - containerPort: 80
        hostPort: 19001
        listenAddress: "0.0.0.0"
        protocol: TCP
      - containerPort: 80
        hostPort: 19002
        listenAddress: "0.0.0.0"
        protocol: TCP
      - containerPort: 80
        hostPort: 19003
        listenAddress: "0.0.0.0"
        protocol: TCP
      # Lablara ayrılmış özel NodePort port alanları
      - containerPort: 30086
        hostPort: 30086
        listenAddress: "0.0.0.0"
        protocol: TCP
      - containerPort: 30087
        hostPort: 30087
        listenAddress: "0.0.0.0"
        protocol: TCP
      - containerPort: 30088
        hostPort: 30088
        listenAddress: "0.0.0.0"
        protocol: TCP
      - containerPort: 30089
        hostPort: 30089
        listenAddress: "0.0.0.0"
        protocol: TCP
    extraMounts:
      # Static PV için host dizin eşlemesi
      - hostPath: /opt/k8s-labs/static-pv
        containerPath: /mnt/k8s-labs/static-pv
  - role: worker
    extraMounts:
      - hostPath: /opt/k8s-labs/static-pv
        containerPath: /mnt/k8s-labs/static-pv
  - role: worker
    extraMounts:
      - hostPath: /opt/k8s-labs/static-pv
        containerPath: /mnt/k8s-labs/static-pv
```

### Yapılandırmada Neler Tanımlandı?
- **3 Düğümlü Mimari:** 1 adet `control-plane` ve 2 adet `worker` node kurulur.
- **`ingress-ready=true`:** NGINX Ingress ve Traefik Gateway Pod'larının doğrudan control-plane üzerinde konumlanmasını sağlar.
- **Port Eşlemeleri (`extraPortMappings`):**
  - `19001-19003`: Ingress / Gateway API HTTP trafiğini Kind control-plane'in `:80` portuna yönlendirir.
  - `30086`: Lab 01 (İlk Web Servisi - NodePort).
  - `30087`: Lab 02 & Lab 07 (DevOps Uygulaması - NodePort).
  - `30088`: Lab 04 & Lab 08 (Traefik Gateway API Önizleme - NodePort).
  - `30089`: Lab 10 (Grafana Paneli - NodePort).
- **Disk Bağlantısı (`extraMounts`):** Host makinedeki `/opt/k8s-labs/static-pv` dizini tüm node'larda `/mnt/k8s-labs/static-pv` konumuna monte edilir.

---

## 4. Kind Cluster'ı Başlatma ve Doğrulama

Kümeyi oluşturmak için:

```bash
cd ~/k8s-labs
kind create cluster --name k8s-labs --config kind-cluster.yaml
```

Oluşturulan kümenin hazır olduğunu kontrol edin:

```bash
kubectl config use-context kind-k8s-labs
kubectl get nodes -o wide
```

**Beklenen sonuç:** Üç node (`k8s-labs-control-plane`, `k8s-labs-worker`, `k8s-labs-worker2`) `Ready` durumunda listelenmelidir.

---

## 5. Laboratuvarlar ve Çalışma Dizinleri

Tüm lab geçişlerinde terminalinizden aşağıdaki tam dizin adreslerini kullanabilirsiniz:

| Sıra | Lab Başlığı | Port | Tam Çalışma Dizini | Rehber |
| :---: | :--- | :---: | :--- | :---: |
| **1** | İlk Uygulaman: Pod, Deployment ve Service | `30086` | `cd ~/k8s-labs/lab-01-first-app-pod-deployment-and-services` | [Rehber](lab-01-first-app-pod-deployment-and-services/README.md) |
| **2** | Kendi Docker İmajını Private Docker Hub'dan Çalıştır | `30087` | `cd ~/k8s-labs/lab-02-private-dockerhub-image-configmap-secret` | [Rehber](lab-02-private-dockerhub-image-configmap-secret/README.md) |
| **3** | Uygulamanı NGINX Ingress ile İnternete Aç | `19001` | `cd ~/k8s-labs/lab-03-nginx-ingress-routing` | [Rehber](lab-03-nginx-ingress-routing/README.md) |
| **4** | Ingress Kurallarını Gateway API'ye Taşı | `19001`, `30088` | `cd ~/k8s-labs/lab-04-ingress-to-gateway-api` | [Rehber](lab-04-ingress-to-gateway-api/README.md) |
| **5** | Veriyi Kaybetme: PV, PVC, Static ve Dynamic Storage | - | `cd ~/k8s-labs/lab-05-static-and-dynamic-storage` | [Rehber](lab-05-static-and-dynamic-storage/README.md) |
| **6** | Paylaşımlı Depolama ve StatefulSet ile MySQL | - | `cd ~/k8s-labs/lab-06-nfs-storage-and-statefulset` | [Rehber](lab-06-nfs-storage-and-statefulset/README.md) |
| **7** | Her Node'da Ajan Çalıştır ve Uygulamanı Otomatik Ölçekle | `30087` | `cd ~/k8s-labs/lab-07-daemonset-and-hpa-scaling` | [Rehber](lab-07-daemonset-and-hpa-scaling/README.md) |
| **8** | Sürümü Güvenle Yayınla (Recreate, Rolling, Blue-Green, Canary) | `19001` | `cd ~/k8s-labs/lab-08-deployment-strategies` | [Rehber](lab-08-deployment-strategies/README.md) |
| **9** | WordPress ile Helm Operasyonlarını Öğren | `8088` | `cd ~/k8s-labs/lab-09-wordpress-ile-helm-operasyonlari` | [Rehber](lab-09-wordpress-ile-helm-operasyonlari/README.md) |
| **10** | Prometheus ve Grafana ile Küme ve Sistem Metriklerini İzle | `30089` | `cd ~/k8s-labs/lab-10-prometheus-grafana-monitoring` | [Rehber](lab-10-prometheus-grafana-monitoring/README.md) |
| **11** | LimitRange ve ResourceQuota | - | `cd ~/k8s-labs/lab-11-limitrange-resourcequota` | [Rehber](lab-11-limitrange-resourcequota/README.md) |
| **12** | Basit RBAC: ServiceAccount, Role ve RoleBinding | - | `cd ~/k8s-labs/lab-12-basit-rbac` | [Rehber](lab-12-basit-rbac/README.md) |
| **13** | Headlamp Görsel Gösterge Paneli ve Güvenli Küme İzleme | `18084` | `cd ~/k8s-labs/lab-13-headlamp-cluster-dashboard` | [Rehber](lab-13-headlamp-cluster-dashboard/README.md) |

---

## 6. Eğitim Sunucusu Güvenlik Duvarı Port Listesi

Eğitim sunucusunun güvenlik grubunda (Security Group / UFW) dışarıdan erişim için açılması gereken TCP portları:

- **`22`**: SSH erişimi.
- **`30086`**: Lab 01 Web Servisi.
- **`30087`**: Lab 02 & Lab 07 DevOps Uygulaması.
- **`30088`**: Lab 04 & Lab 08 Traefik Gateway API Önizleme.
- **`30089`**: Lab 10 Grafana Görsel İzleme Arayüzü (`http://SUNUCU_IP:30089`).
- **`19001`**: Lab 03, Lab 04, Lab 08 Ingress / Gateway API Ana HTTP Girişi.
- **`8088`**: Lab 09 WordPress Web Paneli (`kubectl port-forward --address 0.0.0.0 ... 8088:80`).
- **`18084`**: Lab 13 Headlamp Küme Yönetim Paneli (`kubectl port-forward --address 0.0.0.0 ... 18084:80`).
- **`19090`**: Lab 10 Prometheus Metrik Arayüzü.

*(Eğer sunucu önünde Nginx Edge Proxy veya Cloudflare SSL kullanılıyorsa, dış dünyaya sadece `80` ve `443` portları açılır).*

---

## 7. Hızlı Başvuru

Günlük kullanımda sık ihtiyaç duyulan `kubectl` ve `kind` komutları için:
- 📖 [Kubectl ve Kind Hızlı Başvuru Kılavuzu](cheat-sheets/kubectl-ve-kind-hizli-basvuru.md)
