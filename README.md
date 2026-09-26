# Kubernetes Labs

Bu laboratuvar serisi; temel Kubernetes nesnelerinden başlayarak uygulama yayınlama, ağ yönetimi, kalıcı depolama, otomatik ölçekleme, güvenlik, dağıtım stratejileri, Helm ve monitoring konularına kadar uçtan uca pratik yapmanızı sağlar.

Lablar üç seviyede ve pedagojik sırayla düzenlenmiştir:

```text
Beginner → Intermediate → Advanced
```

- **Beginner:** Kubernetes'e ilk kez başlayan öğrenciler için temel kaynaklar.
- **Intermediate:** Uygulama yayınlama, ölçekleme, hata ayıklama ve güvenlik.
- **Advanced:** Gateway API, StatefulSet, ileri deployment stratejileri, Helm ve monitoring.

> [!IMPORTANT]
> Bütün lablar `k8s-labs` adlı, bir control-plane ve iki worker node'dan oluşan **Kind (Kubernetes in Docker)** cluster'ı için hazırlanmıştır. Lablarda kullanılan ingress, servis portları ve kalıcı disk bağlama noktaları önceden belirlenmiş mimariye göre yapılandırılmıştır.

---

## 1. Sistem Gereksinimleri ve Ön Kontrol

Laboratuvarları çalıştırabilmek için sisteminizde (Ubuntu 20.04/22.04/24.04 önerilir) aşağıdaki dört temel aracın kurulu olması gerekir:

1. **Docker:** Konteyner motoru ve Kind node'larının üzerinde çalışacağı ortam.
2. **Kind:** Docker konteynerleri içinde çok düğümlü yerel Kubernetes cluster'ı çalıştıran araç.
3. **kubectl:** Kubernetes API sunucusu ile iletişim kuran resmi komut satırı aracı.
4. **Helm:** WordPress, Traefik, Prometheus ve Headlamp kurulumlarında kullanılan Kubernetes paket yöneticisi.

Araçların kurulu olup olmadığını kontrol edin:

```bash
docker --version
kind version
kubectl version --client
helm version --short
```

Her komutun çıktısında geçerli bir sürüm numarası görünmelidir. Bir araç eksikse aşağıdaki otomatik veya manuel kurulum adımlarını uygulayın.

---

## 2. Altyapı Kurulumu

### Seçenek A: Otomatik Kurulum (Önerilen)

Tüm araçları, Docker izinlerini ve kalıcı disk dizinlerini idempotent kurulum betiğiyle hazırlayabilirsiniz:

```bash
cd ~/k8s-labs
chmod +x install-prerequisites.sh
./install-prerequisites.sh
```

Betik, sistemde kurulu araçları atlar; yalnızca eksik bileşenleri kurar ve storage labı için gereken dizini hazırlar.

---

### Seçenek B: Adım Adım Manuel Kurulum (Ubuntu)

#### 1. Temel sistem paketleri

```bash
sudo apt-get update -y
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release git conntrack jq
```

#### 2. Docker CE kurulumu

Docker, Kind'in çalışması için zorunlu konteyner motorudur.

```bash
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker

sudo usermod -aG docker "$USER"
newgrp docker 2>/dev/null || true
```

#### 3. kubectl kurulumu

```bash
K8S_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
ARCH=$(dpkg --print-architecture)
curl -sLO "https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/${ARCH}/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm -f kubectl
```

#### 4. Kind kurulumu

```bash
KIND_VERSION="v0.27.0"
ARCH=$(dpkg --print-architecture)
curl -sLo ./kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-${ARCH}"
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind
```

#### 5. Helm kurulumu

```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

#### 6. Static PV dizinini hazırla

Beginner Lab 04'te kullanılacak static PersistentVolume'un host üzerinde yazabilmesi için:

```bash
sudo mkdir -p /opt/k8s-labs/static-pv
sudo chmod 0777 /opt/k8s-labs/static-pv
```

---

## 3. Kind Cluster Yapılandırması (`kind-cluster.yaml`)

Laboratuvarların sorunsuz çalışabilmesi için Kind cluster'ı özel bir ağ ve disk sözleşmesiyle yapılandırılmıştır:

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

### Yapılandırmada neler tanımlandı?

- **Üç node'lu mimari:** Bir control-plane ve iki worker node oluşturulur.
- **`ingress-ready=true`:** NGINX Ingress ve Traefik Gateway Pod'larının control-plane üzerinde konumlandırılabilmesini sağlar.
- **`19001–19003`:** Ingress ve Gateway API trafiği için ayrılmış host portlarıdır.
- **`30086–30089`:** NodePort kullanan lablar için ayrılmış portlardır.
- **`extraMounts`:** Host makinedeki `/opt/k8s-labs/static-pv` dizinini bütün node'larda `/mnt/k8s-labs/static-pv` konumuna bağlar.

---

## 4. Kind Cluster'ı Başlatma ve Doğrulama

Cluster'ı oluşturun:

```bash
cd ~/k8s-labs
kind create cluster --name k8s-labs --config kind-cluster.yaml
```

Doğru context'i seçip node'ları doğrulayın:

```bash
kubectl config use-context kind-k8s-labs
kubectl get nodes -o wide
```

Beklenen sonuç:

```text
k8s-labs-control-plane   Ready
k8s-labs-worker          Ready
k8s-labs-worker2         Ready
```

Cluster zaten varsa yeniden oluşturmayın. Mevcut durumu kontrol edin:

```bash
kind get clusters
kubectl config current-context
kubectl get nodes
```

Cluster'ı tamamen sıfırlamak gerektiğinde bütün lab cleanup adımlarını uyguladıktan sonra:

```bash
kind delete cluster --name k8s-labs
kind create cluster --name k8s-labs --config kind-cluster.yaml
```

---

## 5. Beginner Labları

[Beginner bölüm özeti](beginner/README.md)

| Sıra | Lab ve doğrudan rehber | Kısa özet | Süre | Durum |
|---:|---|---|---:|---|
| B1 | [Cluster, kubectl, Namespace, Label ve Selector](beginner/lab-01-cluster-kubectl-namespace-labels/README.md) | Cluster'ı keşfetme, API kaynakları, namespace ve selector kullanımı | 35–45 dk | Zorunlu |
| B2 | [Pod, Deployment, Service ve DNS](beginner/lab-02-pod-deployment-service/README.md) | Pod, self-healing, Service türleri, Service Discovery, DNS ve EndpointSlice | 100–120 dk | Zorunlu |
| B3 | [ConfigMap, Secret ve Private Image](beginner/lab-03-configmap-secret-private-image/README.md) | ConfigMap ve Secret kullanımı; ek görevde private registry erişimi | 45–75 dk | Çekirdek + ek görev |
| B4 | [PV, PVC, Static ve Dynamic Storage](beginner/lab-04-pv-pvc-storage/README.md) | Static ve dynamic provisioning ile kalıcı veri yönetimi | 55–70 dk | Zorunlu |

## 6. Intermediate Labları

[Intermediate bölüm özeti](intermediate/README.md)

| Sıra | Lab ve doğrudan rehber | Kısa özet | Süre | Durum |
|---:|---|---|---:|---|
| I1 | [NGINX Ingress ve DNS](intermediate/lab-01-ingress-and-dns/README.md) | Host tabanlı dış trafik yönlendirme ve yerel Host header testi | 55–70 dk | Zorunlu |
| I2 | [ResourceQuota ve LimitRange](intermediate/lab-02-resourcequota-and-limitrange/README.md) | Namespace kaynak bütçesi ve varsayılan container limitleri | 40–50 dk | Zorunlu |
| I3 | [HPA ve DaemonSet](intermediate/lab-03-daemonset-and-hpa/README.md) | HPA ile otomatik ölçekleme; ek görevde her node'da ajan çalıştırma | 55–70 dk | Çekirdek + ek görev |
| I4 | [Probes, Resources ve Troubleshooting](intermediate/lab-04-probes-resources-troubleshooting/README.md) | Sağlık kontrolleri, kaynak yönetimi ve yaygın Pod hatalarının teşhisi | 60–75 dk | Zorunlu |
| I5 | [Recreate ve RollingUpdate](intermediate/lab-05-recreate-and-rolling-update/README.md) | Temel deployment stratejileri, kesinti gözlemi ve rollback | 55–70 dk | Seviyeye göre |
| I6 | [Basit RBAC](intermediate/lab-06-rbac/README.md) | ServiceAccount, Role ve RoleBinding ile en az yetki | 40–50 dk | Seviyeye göre |

## 7. Advanced Labları

[Advanced bölüm özeti](advanced/README.md)

| Sıra | Lab ve doğrudan rehber | Kısa özet | Süre | Ön koşul |
|---:|---|---|---:|---|
| A1 | [Gateway API](advanced/lab-01-gateway-api/README.md) | Ingress kurallarından rol tabanlı Gateway API modeline geçiş | 60–75 dk | I1 |
| A2 | [NFS ve StatefulSet](advanced/lab-02-nfs-and-statefulset/README.md) | RWX paylaşımlı depolama ve durum bilgili MySQL workload'u | 70–90 dk | B4 |
| A3 | [Blue-Green ve Canary](advanced/lab-03-blue-green-and-canary/README.md) | Service seçicisi, Pod oranı ve Gateway ağırlıklarıyla ileri yayın | 75–100 dk | I5 |
| A4 | [Helm Operasyonları](advanced/lab-04-helm-operations/README.md) | Install, upgrade, rollback ve uninstall işlemleri | 60–75 dk | B4 |
| A5 | [Prometheus ve Grafana](advanced/lab-05-prometheus-grafana/README.md) | Metrik toplama, PromQL, dashboard ve alarm yönetimi | 90–120 dk | Helm |
| A6 | [Headlamp Dashboard](advanced/lab-06-headlamp-cluster-dashboard/README.md) | Salt-okunur RBAC ile görsel cluster yönetimi | 45–60 dk | I6 ve Helm |
| A7 | [Scheduling ve Node Bakımı](advanced/lab-07-scheduling-and-node-maintenance/README.md) | nodeSelector, taint, toleration, cordon ve drain | 50–65 dk | B1 |

---

## 8. Öğrenci Seviyesine Göre Eğitim Rotası

### Başlangıç sınıfı

```text
B1 → B2 temel nesneler → B3 çekirdek → I2 → B2 DNS bölümü → I1 → B4 → I4
```

Private registry, HPA ve deployment stratejileri zaman kalırsa ek görev olarak uygulanır.

### Orta seviye sınıf

```text
B1 hızlı kontrol → B2 → B3 → I1 → B4 → I2 → I3 → I4 → I5 → I6
```

### Hızlı veya ileri sınıf

Intermediate rota tamamlandıktan sonra ihtiyaca göre A1, A2, A3 veya A7 seçilir. Helm, monitoring ve yönetim arayüzleri daha uzun uygulama süresi gerektirir.

---

## 9. Önerilen İki Günlük Akış

Docker içeriği [docker-labs](https://gitlab.com/devops-practitioner-labs/docker-labs) repository'sinde uygulanır. Eğitim süresinin yaklaşık `%80`i Kubernetes'e ayrılır.

### 1. gün

| Saat | Konu |
|---|---|
| 09:00–10:30 | Docker tekrar ve Docker labları |
| 10:30–11:00 | Orchestration ve Kubernetes mimarisi |
| 11:00–12:00 | B1 – Cluster ve kubectl |
| 13:00–14:30 | B2 – Pod, Deployment ve Service |
| 14:45–15:45 | B3 – ConfigMap ve Secret |
| 16:00–17:00 | I2 – LimitRange ve ResourceQuota |

### 2. gün

| Saat | Konu |
|---|---|
| 09:00–10:00 | B2 – Service Discovery ve DNS bölümü |
| 10:15–11:30 | I1 – Ingress |
| 11:30–12:30 | B4 – PV/PVC |
| 13:30–14:30 | I3 – HPA |
| 14:45–15:45 | I4 – Troubleshooting ve probes |
| 16:00–17:00 | Sınıf seviyesine göre tekrar, I5 veya advanced demo |

---

## 10. Eğitim Sunucusu Portları

| Port | Kullanım |
|---:|---|
| `22` | SSH erişimi |
| `19001` | I1 NGINX Ingress, A1 Gateway API veya A3 Gateway tabanlı canary |
| `19002`, `19003` | Ek Ingress/Gateway trafik slotları |
| `30086` | B2 NodePort web servisi |
| `30087` | B3 uygulaması |
| `30088` | A1 Gateway API preview |
| `30089` | A5 Grafana NodePort |
| `8088` | A4 WordPress port-forward |
| `18084` | A6 Headlamp port-forward |
| `19090` | A5 Prometheus port-forward |

Sunucu önünde Nginx Edge Proxy veya benzer bir ters proxy kullanılıyorsa dış dünyaya yalnızca gerekli portları açın.

---

## 11. Lab Çalışma Düzeni

Her lab README'sindeki çalışma dizinine geçin, adımları sırayla uygulayın ve bir sonraki laba geçmeden önce ilgili temizlik bölümünü çalıştırın. Aynı cluster üzerinde kullanılan namespace, port ve controller bileşenleri lab rehberlerinde ayrıca belirtilmiştir.

## 12. Hızlı Başvuru

Sık kullanılan komutlar için [kubectl ve Kind hızlı başvuru kılavuzunu](cheat-sheets/kubectl-ve-kind-hizli-basvuru.md) kullanın.
