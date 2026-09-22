# Kind Kurulumu ve Port Sözleşmesi

Bu eğitim, Azure öğrenci sunucusunda çalışan Edge Nginx, Cloudflare DNS veya mevcut Nginx yapılandırmasını değiştirmez.

## Erişim akışı

```text
Öğrenci tarayıcısı
  → https://student01-app1.devopsatolyesi.com
  → Edge Nginx :443                  TLS burada biter
  → 127.0.0.1:19001
  → Kind control-plane :80
  → NGINX Ingress veya Gateway API
  → ClusterIP Service
  → devops-app Pod
```

DNS adı `student01-app1.devopsatolyesi.com` biçimindedir. `student01.app1...` biçimi kullanılmaz.

## Ayrılmış portlar

| Port | Sahibi | Eğitimdeki rol |
| --- | --- | --- |
| `80`, `443` | Edge Nginx | Değiştirilmez; Kind bu portlara bağlanmaz. |
| `18081`, `18443` | Eski/opsiyonel Kind labları | Kullanılmaz. |
| `19001`, `19002`, `19003` | app1, app2, app3 slotları | Kind control-plane içindeki `:80` için host eşlemesi. |
| `30080-30085` | NovaShop | Kullanılmaz. |
| `30086` | Kubernetes labs | Service türleri NodePort testi. |
| `30087` | Kubernetes labs | Private `devops-app` NodePort testi. |
| `30088` | Kubernetes labs | Gateway API preview NodePort testi. |
| `30089` | Kubernetes labs | Kalıcı Grafana NodePort erişimi. |
| `30090` | Traefik/dashboard | Kullanılmaz. |

`18443` temel-orta seviye akışta gerekli değildir. Dış HTTPS Edge Nginx'te sonlanır; cluster içi TLS ileri seviye bir konudur.

## Küme tanımı

`platform/kind-cluster.yaml` üç node oluşturur: bir control-plane ve iki worker. Control-plane içindeki `:80`, yukarıdaki üç app slotuna eşlenir. `extraMounts` ile `/opt/k8s-labs/static-pv` dizini her Kind node'una `/mnt/k8s-labs/static-pv` olarak bağlanır; static HostPath PV labı bu yolu kullanır.

## Kurulum sırası

```bash
git clone https://gitlab.com/devops-practitioner-labs/k8s-labs.git
cd k8s-labs
kind create cluster --name k8s-labs --config platform/kind-cluster.yaml
```

Adım adım port kontrolü, eklenti kurulumu ve cluster doğrulaması için [Platform Hazırlığı](../platform/README.md) dokümanını kullanın. Hiçbir adım Edge Nginx veya Cloudflare yapılandırmasını değiştirmez.

## Ingress ve Gateway API tercihi

- Ingress labında NGINX Ingress, Kind içindeki `:80` üzerinde çalışır.
- Gateway API labında önce `30088` preview yapılır.
- Cutover aşamasında sadece Kind içindeki NGINX Ingress kaldırılır; Traefik control-plane `:80` üzerinde çalışır.
- Host'suz fallback Ingress veya HTTPRoute yoktur. Bu sayede başka öğrenci uygulamasının trafiği yanlış yakalanmaz.
- Doğrudan host IP/port testi Ingress yerine NodePort Service ile yapılır.
