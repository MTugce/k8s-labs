# * Headlamp Görsel Gösterge Paneli ve Güvenli Küme İzleme

## Amaç

- Kubernetes kümesini görselleştirmek ve yönetmek için modern ve güvenli **Headlamp** web arayüzünü Helm ile kurmak.
- `cluster-admin` gibi sınırsız yönetici yetkisi yerine **En Az Yetki İlkesine (Least Privilege)** uygun salt-okunur (`Read-Only`) bir `ServiceAccount` yapılandırmak.
- Token tabanlı kimlik doğrulama ile Headlamp paneline giriş yapmak.
- `kubectl auth can-i` ve web arayüzü üzerinden yetki sınırlarını (Pod listeleme serbest, Secret okuma ve Pod silme yasak) doğrulamak.

## Kullanılan Kubernetes nesneleri

- **Helm Release:** Headlamp web arayüzü Pod ve Service bileşenlerini kurar ve yönetir.
- **ServiceAccount:** Headlamp arayüzüne giriş yapacak olan kimliği temsil eder (`headlamp-viewer`).
- **ClusterRole:** Küme genelinde hangi kaynakların okunabileceğini belirleyen yetki kuralıdır (`headlamp-viewer-role`).
- **ClusterRoleBinding:** Oluşturulan ServiceAccount ile ClusterRole nesnesini birbirine bağlar (`headlamp-viewer-binding`).

## Çalışma dizini

```bash
cd ~/k8s-labs/lab-13-headlamp-cluster-dashboard
```

## Erişim ve Ağ Mimarisi

Headlamp servisine iki farklı yolla erişilebilir:

| Erişim Türü | Adres / Port | Açıklama |
| --- | --- | --- |
| **Nginx Edge Proxy (HTTPS)** | `https://KULLANICI-headlamp.ALAN_ADI` | Host üzerindeki `127.0.0.1:18084` portuna yönlenir |
| **Port-Forward (Doğrudan)** | `http://127.0.0.1:18084` | Doğrudan geliştirici tünelidir |

- **Kimlik Doğrulama:** Token (Bearer JWT Token)

## Başlamadan önce

Kind kümesinin çalıştığını doğrula:

```bash
kubectl get nodes -o wide
```

Beklenen sonuç: 1 control-plane ve 2 worker node `Ready` durumunda listelenmelidir.

---

## 1. Headlamp Helm Deposunu Ekle ve Kurulumu Başlat

Headlamp, Kubernetes SIGs tarafından desteklenen modern, kullanıcı dostu ve Kubernetes Dashboard'un yerini alan hafif bir küme yönetim arayüzüdür.

Helm deposunu sisteme ekle ve paketi `headlamp` namespace'i içine kur:

```bash
helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/
helm repo update

helm upgrade --install headlamp headlamp/headlamp \
  --namespace headlamp \
  --create-namespace \
  --wait --timeout 5m
```

Kurulan bileşenlerin durumunu doğrula:

```bash
kubectl -n headlamp get pods,svc
```

Beklenen sonuç: `headlamp` pod'u `Running` durumunda olur ve ClusterIP tipinde bir servis listelenir.

---

## 2. Nginx Edge Proxy ve Doğrudan Erişim Portunu Bağla

Nginx Edge Proxy şablonundaki `18084` portunun Headlamp servisine ulaşabilmesi ve tarayıcıdan HTTPS ile açılabilmesi için port yönlendirmesini arka planda başlat:

```bash
kubectl -n headlamp port-forward --address 127.0.0.1 svc/headlamp 18084:80 >/dev/null 2>&1 &
```

Portun aktif olduğunu kontrol et:

```bash
curl -I http://127.0.0.1:18084
```

Beklenen sonuç: HTTP 200 yanıtı alınır. Artık hem `https://KULLANICI-headlamp.ALAN_ADI` üzerinden hem de yerel olarak `http://127.0.0.1:18084` adresinden erişilebilir.

---

## 3. En Az Yetki İlkesiyle Salt-Okunur RBAC Yetkilendirmesi

Gerçek kurumsal ortamlarda küme panellerine `cluster-admin` gibi sınırsız tam yetki verilmez. Güvenlik açığı oluşmaması için:
- Pod, Deployment, Node ve Namespace listeleme/okuma yetkisi verilir.
- Parolaların ve sertifikaların bulunduğu `Secret` nesneleri bilerek kapsam dışı bırakılır.
- Pod silme veya yapılandırma değiştirme gibi yazma yetkileri engellenir.

Bu yetki sözleşmesi `starter/01-headlamp-viewer-rbac.yaml` dosyasında hazırlanmıştır:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: headlamp-viewer
  namespace: headlamp
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: headlamp-viewer-role
rules:
  - apiGroups: [""]
    resources:
      - configmaps
      - endpoints
      - events
      - namespaces
      - nodes
      - persistentvolumeclaims
      - persistentvolumes
      - pods
      - pods/log
      - services
      - serviceaccounts
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources:
      - daemonsets
      - deployments
      - replicasets
      - statefulsets
    verbs: ["get", "list", "watch"]
  - apiGroups: ["batch"]
    resources:
      - cronjobs
      - jobs
    verbs: ["get", "list", "watch"]
  - apiGroups: ["networking.k8s.io"]
    resources:
      - ingresses
      - networkpolicies
    verbs: ["get", "list", "watch"]
  - apiGroups: ["storage.k8s.io"]
    resources:
      - storageclasses
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: headlamp-viewer-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: headlamp-viewer-role
subjects:
  - kind: ServiceAccount
    name: headlamp-viewer
    namespace: headlamp
```

Manifesti kümeye uygula:

```bash
kubectl apply -f starter/01-headlamp-viewer-rbac.yaml
```

Oluşturulan hesap ve bağlayıcıyı doğrula:

```bash
kubectl -n headlamp get serviceaccount headlamp-viewer
kubectl get clusterrolebinding headlamp-viewer-binding
```

---

## 4. Giriş Token'ı Üret

Kubernetes API'si ile kimlik doğrulaması yapmak için `headlamp-viewer` hesabına ait bir oturum token'ı oluştur:

```bash
kubectl create token headlamp-viewer -n headlamp --duration=8h
```

Ekrana gelen uzun JWT token değerini kopyala.

---

## 5. Headlamp Web Arayüzüne Giriş Yap ve Paneli İncele

1. Tarayıcında Headlamp arayüzünü aç:
   - HTTPS Alan Adı: `https://KULLANICI-headlamp.ALAN_ADI`
   - Veya Yerel Adres: `http://127.0.0.1:18084`
2. Giriş ekranında **Token** (veya **ID token**) kutucuğuna tıkla.
3. Kopyaladığın token'ı yapıştır ve **Sign In** butonuna bas.

Arayüzde başarıyla oturum açıldıktan sonra şu sekmeleri incele:
- **Cluster Overview:** Kümedeki node durumları, toplam CPU ve RAM kapasitesi.
- **Workloads -> Pods / Deployments:** Kümede çalışan iş yükleri, replika sayıları ve durumları.
- **Network -> Services / Ingresses:** Tanımlı servisler ve yönlendirme kuralları.
- **Storage -> StorageClasses / PVCs:** Kümedeki depolama alanları.

---

## 6. Güvenlik ve İzin Sınırlarını Test Et

Güvenlik sınırlarının doğru çalıştığını iki yöntemle sına:

### A. Web Arayüzünde Test
1. Sol menüden **Configuration -> Secrets** sekmesine git.
   - **Gözlem:** Yetki verilmediği için gizli değerlerin listelenmediğini veya erişim engeli (Forbidden / 403) uyarısı verildiğini gör.
2. Herhangi bir Pod detayına giderek sağ üstteki **Delete** (Sil) butonuna basmayı dene.
   - **Gözlem:** İşlem API sunucusu tarafından reddedilir.

### B. Terminalden Yetki Simülasyonu (`kubectl auth can-i`)
Terminalden `kubectl auth can-i` komutuyla `headlamp-viewer` hesabının yetkilerini doğrula:

```bash
# Pod'ları listeleme izni (Beklenen: yes)
kubectl auth can-i get pods --as=system:serviceaccount:headlamp:headlamp-viewer

# Node durumlarını inceleme izni (Beklenen: yes)
kubectl auth can-i get nodes --as=system:serviceaccount:headlamp:headlamp-viewer

# Gizli bilgileri (Secret) okuma izni (Beklenen: no)
kubectl auth can-i get secrets --as=system:serviceaccount:headlamp:headlamp-viewer

# Pod silme izni (Beklenen: no)
kubectl auth can-i delete pods --as=system:serviceaccount:headlamp:headlamp-viewer
```

Beklenen sonuç: Okuma izinlerinde `yes`, gizli bilgi okuma ve silme girişimlerinde `no` yanıtı alınır.

---

## Doğal Doğrulama ve Beklenen Sonuç

Tüm bileşenlerin sağlıklı olduğunu doğrula:

```bash
kubectl -n headlamp get pods -l app.kubernetes.io/name=headlamp
kubectl -n headlamp get svc -l app.kubernetes.io/name=headlamp
```

| Bileşen | Beklenen Durum |
| --- | --- |
| Headlamp Pod | 1/1 Running |
| Headlamp Service | ClusterIP (Port 80) |
| Port 18084 | Erişilebilir (HTTP 200) |
| RBAC ServiceAccount | `headlamp-viewer` (Secrets kapalı, salt-okunur) |

> [!NOTE]
> Headlamp arayüzü küme yönetimi ve görsel takip için kurulmuş olup sonraki çalışmalarda da aktif olarak kullanılabilir.
