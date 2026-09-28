# Lab 01: Imperative kubectl ve İlk Podlar


## Amaç

Bu laboratuvarda [Kubernetes Quick Reference](https://kubernetes.io/docs/reference/kubectl/quick-reference/) kılavuzundaki temel **imperative (emirsel)** komutları kullanarak Kubernetes kümesinde ilk Pod'unuzu çalıştıracak, durumunu ve loglarını inceleyecek, konteyner içine bağlanarak komut koşturacak ve `port-forward` ile uygulamaya erişeceksiniz.


Ardından `--dry-run=client -o yaml` tekniği ile emirsel komuttan **declarative (deklaratif/manifest)** YAML şablonu üretmeyi ve `kubectl apply` ile yönetmeyi öğreneceksiniz.

---

## Temel Kavramlar

| Kavram | Açıklama |
|---|---|
| **Pod** | Kubernetes'in en küçük dağıtılabilir işlem birimidir; bir veya birden fazla konteyneri barındırır. |
| **Imperative (Emirsel)** | Kümeye doğrudan ne yapacağını söyleyen tek satırlık CLI komutlarıdır (`kubectl run`, `kubectl delete`). Hızlı test ve prototipleme için idealdir. |
| **Declarative (Bildirimsel)** | İstenen nihai durumu bir YAML dosyasında (manifest) tanımlayıp kümeye sunma yaklaşımıdır (`kubectl apply -f`). GitOps ve üretim ortamlarının standardıdır. |
| **Dry-Run** | Komutu kümeye göndermeden sadece istemci tarafında çalıştırıp manifest çıktısı üretme tekniğidir (`--dry-run=client -o yaml`). |

---

## Çalışma Dizini

```bash
cd ~/k8s-labs/beginner/lab-01-imperative-kubectl-and-pod-basics
```

---

## 1. İzole Namespace Oluşturma

Çalışmalarımızın diğer laboratuvarlarla çakışmaması için `beginner-basics` adında izole bir namespace oluşturalım:

```bash
kubectl create namespace beginner-basics --dry-run=client -o yaml | kubectl apply -f -
```

---

## 2. Imperative Komutla İlk Pod'u Başlatma (`kubectl run`)

Herhangi bir YAML dosyası yazmadan, tek bir komutla Nginx web sunucusu çalıştıran bir Pod başlatalım:

```bash
kubectl run my-first-pod --image=nginx:1.27-alpine --port=80 -n beginner-basics
```

Pod'un durumunu ve çalıştığı node'u listeleyin:

```bash
kubectl get pods -n beginner-basics -o wide
```

**Beklenen sonuç:**
```text
NAME           READY   STATUS    RESTARTS   AGE   IP           NODE               NOMINATED NODE   READINESS GATES
my-first-pod   1/1     Running   0          10s   10.244.x.x   k8s-labs-worker    <none>           <none>
```

---

## 3. Pod Durumu, Olaylar (Events) ve Logları İnceleme

Konteynerin nasıl çekildiğini, IP adresini ve olası başlatma adımlarını incelemek için `describe` komutunu kullanın:

```bash
kubectl describe pod my-first-pod -n beginner-basics
```

Çıktının altındaki **Events** tablosunda şu yaşam döngüsü adımlarını gözlemleyin:
1. `Scheduled`: Pod'un bir worker node'a atanması.
2. `Pulling / Pulled`: `nginx:1.27-alpine` imajının çekilmesi.
3. `Created`: Konteynerin oluşturulması.
4. `Started`: Konteynerin çalıştırılması.

Nginx'in başlangıç loglarını görüntüleyin:

```bash
kubectl logs my-first-pod -n beginner-basics
```

**Beklenen sonuç:**
Nginx başlangıç mesajları (`Configuration complete; ready for start up`) ekranda görünmelidir.

---

## 4. Konteyner İçinde Canlı Komut Çalıştırma (`exec`)

Konteynerin içine girmeden doğrudan komut çalıştırmak için:

```bash
kubectl exec -n beginner-basics my-first-pod -- nginx -v
kubectl exec -n beginner-basics my-first-pod -- printenv
```

İnteraktif bir kabuk (shell) açmak için:

```bash
kubectl exec -it -n beginner-basics my-first-pod -- sh
```

Kabuk içinde basit bir komut çalıştırıp çıkın:

```sh
cat /etc/os-release
exit
```

---

## 5. Port Yönlendirme ile Uygulamaya Erişme (`port-forward`)

Pod'un 80 portunu geçici olarak yerel bilgisayarınızın 8080 portuna yönlendirin:

```bash
kubectl port-forward -n beginner-basics pod/my-first-pod 8080:80 &
```

*(Komut arka planda çalışacaktır).* 

> [!TIP]
> `port-forward` çıktısı (`Forwarding from 127.0.0.1:8080 -> 80`) ekranda belirdiğinde terminal kilitlenmiş gibi görünürse klavyenizden bir kez `Enter` tuşuna basarak yeni komut satırına geçebilirsiniz. Alternatif olarak ayrı bir terminal sekmesinde `&` koymadan da çalıştırabilirsiniz.

Başka bir komutla curl isteği atarak Nginx karşılama sayfasını doğrulayın:

```bash
curl -I http://127.0.0.1:8080
```

**Beklenen sonuç:**
```text
HTTP/1.1 200 OK
Server: nginx/...
```

Port yönlendirmeyi sonlandırmak için arka plandaki işlemi durdurun:

```bash
kill %1 2>/dev/null || pkill -f "port-forward.*8080"
```

---

## 6. Imperative'den Declarative'e Geçiş: `--dry-run` ile YAML Üretme

Gerçek projelerde Pod'lar elle komut yazılarak değil, Git'te saklanan YAML dosyalarıyla yönetilir. Sıfırdan karmaşık YAML yazmak yerine `kubectl`'den şablon üretebilirsiniz:

```bash
kubectl run my-simple-pod \
  --image=nginx:1.27-alpine \
  --port=80 \
  --dry-run=client -o yaml > starter/my-simple-pod.yaml
```

Üretilen dosyayı inceleyin:

```bash
cat starter/my-simple-pod.yaml
```

Dosyayı declarative olarak kümeye uygulayın:

```bash
kubectl apply -f starter/my-simple-pod.yaml -n beginner-basics
```

Namespace içindeki tüm Pod'ları etiketleriyle birlikte listeleyin:

```bash
kubectl get pods -n beginner-basics --show-labels
```

---

## 7. Temizlik (Cleanup)

Bu laboratuvarda oluşturulan kaynakları temizlemek için:

```bash
kubectl delete namespace beginner-basics
```

Namespace silindiğinde içerisindeki tüm Pod'lar otomatik olarak temizlenir.
