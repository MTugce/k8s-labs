# Lab 02: Pod Tasarım Kalıpları (Multi-Container, Init ve Sidecar)


## Amaç

Bir Pod her zaman tek bir konteynerden ibaret olmak zorunda değildir. Kubernetes'te birbirine sıkı sıkıya bağlı yardımcı süreçler aynı Pod içerisinde koşturulabilir.

Bu laboratuvarda:
1. Aynı Pod içindeki birden fazla konteynerin aynı ağ (`localhost`) ve depolama alanını nasıl paylaştığını (**Multi-Container Pod**),
2. Ana uygulama başlamadan önce ön koşulları yerine getiren hazırlık konteynerlerini (**Init Container**),
3. Ana uygulamanın ürettiği logları ortak bir geçici disk (`emptyDir`) üzerinden okuyup işleyen toplayıcı konteynerleri (**Sidecar Pattern**) uygulamalı olarak öğreneceksiniz.

---

## Kullanılan Kavramlar

| Kalıp / Kavram | Açıklama |
|---|---|
| **Multi-Container Pod** | Aynı Pod içinde çalışan konteynerlerdir. Aynı Linux network namespace'ini paylaşırlar; birbirlerine `localhost` üzerinden erişebilirler. |
| **Init Container** | Ana konteynerler (`spec.containers`) başlamadan önce sırayla çalışan ve başarıyla tamamlanması gereken konteynerlerdir (`spec.initContainers`). |
| **Sidecar Container** | Ana uygulamanın işlevini değiştirmeden ona ek yetenek (log toplama, proxy, metrik çıkarma vb.) kazandıran yardımcı konteynerdir. |
| **emptyDir** | Pod'un yaşam döngüsüne bağlı geçici bir depolama birimidir; Pod içindeki konteynerler arasında dosya paylaşımı sağlar. |

---

## Çalışma Dizini

```bash
cd ~/k8s-labs/beginner/lab-02-pod-design-patterns-multi-init-sidecar
```

---

## 1. İzole Namespace Oluşturma

```bash
kubectl create namespace beginner-patterns --dry-run=client -o yaml | kubectl apply -f -
```

---

## 2. Multi-Container Pod Uygulaması (Nginx + Redis)

`starter/multi-container-pod.yaml` manifestini inceleyin:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: multi-container-pod
  labels:
    app: multi-container
spec:
  containers:
    - name: web
      image: nginx:1.27-alpine
      ports:
        - containerPort: 80
    - name: cache
      image: redis:7.2-alpine
      ports:
        - containerPort: 6379
```

Manifesti uygulayın:

```bash
kubectl apply -f starter/multi-container-pod.yaml -n beginner-patterns
```

Pod'un durumunu izleyin:

```bash
kubectl get pod multi-container-pod -n beginner-patterns
```

**Beklenen sonuç:**
`READY` sütununda `2/2` görünmelidir. Bu, Pod içindeki her iki konteynerin de başarıyla ayağa kalktığını belirtir:
```text
NAME                  READY   STATUS    RESTARTS   AGE
multi-container-pod   2/2     Running   0          15s
```

### Belirli Bir Konteynere Bağlanma (`-c` Parametresi)

Birden fazla konteyner içeren bir Pod'da `logs` veya `exec` çalıştırırken `-c <container-adi>` belirtilmelidir:

```bash
# Redis konteynerinde Redis CLI ile ping testi yapın
kubectl exec -it multi-container-pod -c cache -n beginner-patterns -- redis-cli ping
```

**Beklenen sonuç:** `PONG`

```bash
# Web konteyneri içinden localhost:6379 üzerinden Redis'e erişilebildiğini kanıtlayın
kubectl exec -it multi-container-pod -c web -n beginner-patterns -- nc -zv 127.0.0.1 6379
```

**Beklenen sonuç:** `127.0.0.1 (127.0.0.1:6379) open`  
*(Aynı Pod içindeki konteynerler localhost üzerinden haberleşir).*

---

## 3. Init Container ile Ön Koşul ve Veri Hazırlığı

`starter/init-container-pod.yaml` manifestini inceleyin. Bu manifestte bir `busybox` init container, ana web sunucusu başlamadan önce paylaşılan diske özel bir `index.html` dosyası yazar:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: init-container-pod
  labels:
    app: init-demo
spec:
  initContainers:
    - name: setup-page
      image: busybox:1.37
      command: ['sh', '-c', 'echo "<h1>Init Container Tarafindan Hazirlandi</h1>" > /workdir/index.html']
      volumeMounts:
        - name: shared-data
          mountPath: /workdir
  containers:
    - name: web
      image: nginx:1.27-alpine
      ports:
        - containerPort: 80
      volumeMounts:
        - name: shared-data
          mountPath: /usr/share/nginx/html
  volumes:
    - name: shared-data
      emptyDir: {}
```

Manifesti uygulayın:

```bash
kubectl apply -f starter/init-container-pod.yaml -n beginner-patterns
```

Pod'un durumunu inceleyin:

```bash
kubectl get pod init-container-pod -n beginner-patterns
```

Başlangıçta `STATUS` sütunu `Init:0/1` olarak görünür, init tamamlandığında `PodInitializing` ve ardından `Running` olur.

Init container logunu kontrol edin:

```bash
kubectl logs init-container-pod -c setup-page -n beginner-patterns
```

Web konteynerine istek atarak Init Container'ın yazdığı içeriğin Nginx tarafından sunulduğunu doğrulayın:

```bash
kubectl exec -n beginner-patterns init-container-pod -c web -- wget -qO- http://localhost:80
```

**Beklenen sonuç:**
```html
<h1>Init Container Tarafindan Hazirlandi</h1>
```

---

## 4. Sidecar Container Kalıbı ile Canlı Log İzleme

`starter/sidecar-container-pod.yaml` manifestinde ana Nginx sunucusu erişim loglarını `/var/log/nginx/access.log` dosyasına yazar. Yanındaki `log-sidecar` konteyneri ise aynı dizini `emptyDir` üzerinden bağlayarak logları anlık olarak dışarı aktarır:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: sidecar-container-pod
  labels:
    app: sidecar-demo
spec:
  containers:
    - name: web-app
      image: nginx:1.27-alpine
      ports:
        - containerPort: 80
      volumeMounts:
        - name: log-volume
          mountPath: /var/log/nginx
    - name: log-sidecar
      image: busybox:1.37
      command: ['sh', '-c', 'touch /var/log/nginx/access.log && tail -F /var/log/nginx/access.log']
      volumeMounts:
        - name: log-volume
          mountPath: /var/log/nginx
  volumes:
    - name: log-volume
      emptyDir: {}
```

Manifesti uygulayın:

```bash
kubectl apply -f starter/sidecar-container-pod.yaml -n beginner-patterns
kubectl wait --for=condition=Ready pod/sidecar-container-pod -n beginner-patterns --timeout=60s
```

Web sunucusuna birkaç istek gönderin:

```bash
kubectl exec -n beginner-patterns sidecar-container-pod -c web-app -- wget -qO- http://localhost:80 > /dev/null
kubectl exec -n beginner-patterns sidecar-container-pod -c web-app -- wget -qO- http://localhost:80/test-sayfasi > /dev/null 2>&1 || true
```

Şimdi doğrudan `log-sidecar` konteynerinin loglarını okuyun:

```bash
kubectl logs sidecar-container-pod -c log-sidecar -n beginner-patterns
```

**Beklenen sonuç:**
Nginx erişim logları (`GET / HTTP/1.1" 200`, `GET /test-sayfasi HTTP/1.1" 404`) sidecar konteynerinin standart çıktısında görünmelidir!

---

## 5. Temizlik (Cleanup)

```bash
kubectl delete namespace beginner-patterns
```
