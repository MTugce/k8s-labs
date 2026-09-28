# Lab 08: Pod Sorun Giderme (CrashLoopBackOff ve OOMKilled)

Kubernetes ortamlarında en sık karşılaşılan iki pod çalışma zamanı (runtime) arızası **CrashLoopBackOff** ve **OOMKilled** (Out of Memory) hatalarıdır. Bir DevOps mühendisi olarak bu hataları tanımak, nedenlerini loglar ve olaylar (events) üzerinden analiz etmek ve çözüme kavuşturmak kritik bir beceridir.

Bu laboratuvarda;
1. Hatalı çalışan bir uygulamanın neden **CrashLoopBackOff** durumuna düştüğünü tespit edecek, `kubectl logs --previous` komutuyla geçmiş logları okuyacak ve düzelteceksiniz.
2. Bellek sınırını aşan bir uygulamanın Linux çekirdeği (cgroups OOM Killer) tarafından nasıl sonlandırıldığını (**OOMKilled - Exit Code 137**) gözlemleyecek ve kaynak sınırlarını optimize ederek sorunu çözeceksiniz.

---

## Adım 1: İzole Namespace Oluşturma

Laboratuvar kaynaklarını izole bir alanda çalıştırmak için `beginner-troubleshoot` adında bir namespace oluşturun:

```bash
kubectl create namespace beginner-troubleshoot
```

Çalışma alanınıza geçin:

```bash
cd ~/k8s-labs/beginner/lab-08-pod-troubleshooting-crashloop-oom
```

---

## Bölüm 1: CrashLoopBackOff Analizi ve Çözümü

### Adım 2: Hatalı Pod Manifestini İnceleme ve Dağıtma

`starter/crash-pod.yaml` dosyasını inceleyin:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: crash-demo
  labels:
    app: crash-demo
spec:
  containers:
  - name: broken-app
    image: busybox:1.36
    command: ["sh", "-c", "echo 'Uygulama baslatiliyor...'; sleep 2; echo 'Kritik hata: veritabanina baglanilamadi!'; exit 1"]
```

Bu pod başlatıldıktan 2 saniye sonra `exit 1` koduyla sonlanmaktadır. Kubernetes varsayılan olarak `restartPolicy: Always` kullandığı için çöken konteyneri sürekli yeniden başlatmaya çalışır.

Pod'u dağıtın:

```bash
kubectl apply -f starter/crash-pod.yaml -n beginner-troubleshoot
```

### Adım 3: Pod Durumunu ve Gecikmeli Yeniden Başlatmayı (Back-off) Gözlemleme

Pod'un durumunu izleyin:

```bash
kubectl get pods -n beginner-troubleshoot
```

Çıktıda `STATUS` sütununda önce `Error`, ardından `CrashLoopBackOff` göreceksiniz. `RESTARTS` sayacının arttığına dikkat edin:

```
NAME         READY   STATUS             RESTARTS      AGE
crash-demo   0/1     CrashLoopBackOff   2 (20s ago)   35s
```

> **CrashLoopBackOff Nedir?**
> Bir konteyner sıfır olmayan bir çıkış koduyla (hata ile) sonlandığında, Kubernetes konteyneri hemen yeniden başlatır. Konteyner tekrar çökerse, Kubernetes sistemi ve CPU kaynaklarını korumak için yeniden başlatma aralığını katlanarak artırır (10s, 20s, 40s, 80s... maksimum 5 dakikaya kadar). Bu duruma **Back-off** denir.

### Adım 4: Hatanın Nedenini Tespit Etme (`describe` ve `logs`)

Öncelikle pod olaylarını (events) inceleyin:

```bash
kubectl describe pod crash-demo -n beginner-troubleshoot
```

`Events` bölümünde `Back-off restarting failed container broken-app in pod crash-demo` uyarısını göreceksiniz. Ayrıca `Containers` -> `State` -> `Last State` alanında `Exit Code: 1` yazdığını görebilirsiniz.

Şimdi pod'un loglarını okuyarak uygulamanın neden çöktüğünü anlayın:

```bash
kubectl logs crash-demo -n beginner-troubleshoot
```

Eğer konteyner tam o anda çökmüş ve henüz yenisi ayağa kalkmamışsa, bir önceki çöken konteynerin loglarını okumak için `--previous` bayrağını kullanın:

```bash
kubectl logs crash-demo -n beginner-troubleshoot --previous
```

Çıktı:
```
Uygulama baslatiliyor...
Kritik hata: veritabanina baglanilamadi!
```

Loglarda uygulamanın `exit 1` ile çöktüğü açıkça görülmektedir.

### Adım 5: Sorunu Düzeltme

`starter/crash-fixed-pod.yaml` dosyasında uygulama hatası giderilmiş ve sürekli çalışan sağlıklı bir arka plan süreci tanımlanmıştır:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: crash-demo
  labels:
    app: crash-demo
spec:
  containers:
  - name: broken-app
    image: busybox:1.36
    command: ["sh", "-c", "echo 'Uygulama basariyla baslatildi.'; while true; do echo 'Uygulama saglikli calisiyor...'; sleep 10; done"]
```

Pod'u güncelleyin:

```bash
kubectl replace --force -f starter/crash-fixed-pod.yaml -n beginner-troubleshoot
```

Pod'un durumunu kontrol edin:

```bash
kubectl get pod crash-demo -n beginner-troubleshoot
```

Çıktı:
```
NAME         READY   STATUS    RESTARTS   AGE
crash-demo   1/1     Running   0          5s
```

Pod artık `Running` durumundadır ve yeniden başlatma (restarts) 0'dır!

Temizlik için bu pod'u silin:

```bash
kubectl delete pod crash-demo -n beginner-troubleshoot
```

---

## Bölüm 2: OOMKilled (Out of Memory) Analizi ve Çözümü

### Adım 6: OOM Hatası Üreten Pod Manifestini İnceleme ve Dağıtma

`starter/oom-pod.yaml` dosyasını inceleyin:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: oom-demo
  labels:
    app: oom-demo
spec:
  restartPolicy: Never
  containers:
  - name: memory-eater
    image: alpine:3.21
    command: ["sh", "-c", "echo 'Bellek tuketimi baslatiliyor (100MB ayrilacak)...'; dd if=/dev/zero of=/dev/shm/fill bs=1M count=100; sleep 3600"]
    resources:
      limits:
        memory: "32Mi"
      requests:
        memory: "16Mi"
```

Dikkat edin: Pod için azami bellek sınırı (`limits.memory`) **32Mi** olarak tanımlanmıştır. Ancak uygulama çalışırken `/dev/shm` (RAM diski) üzerine **100MB** veri tahsis etmeye çalışmaktadır. `restartPolicy: Never` tanımlandığı için pod öldüğünde hemen tekrar başlatılmayacak ve durum incelemesi için sabit kalacaktır.

Pod'u dağıtın:

```bash
kubectl apply -f starter/oom-pod.yaml -n beginner-troubleshoot
```

### Adım 7: OOMKilled Durumunu ve Çıkış Kodunu (Exit Code 137) Tespit Etme

Pod durumunu kontrol edin:

```bash
kubectl get pod oom-demo -n beginner-troubleshoot
```

`STATUS` sütununda `OOMKilled` veya `Error` göreceksiniz. Neden çöktüğünü anlamak için `describe` komutunu çalıştırın:

```bash
kubectl describe pod oom-demo -n beginner-troubleshoot
```

Çıktıda `State` alanına dikkat edin:
```
    State:          Terminated
      Reason:       OOMKilled
      Exit Code:    137
```

> **Exit Code 137 ve OOMKilled Nedir?**
> Linux işletim sisteminde bir süreç belirlenen `cgroup memory limit` değerini aştığında, Linux çekirdeği sistemi ve diğer süreçleri korumak için sürece acil `SIGKILL` (Signal 9) sinyali gönderir.
> Linux çıkış kodlarında `128 + Signal Numarası` kuralı geçerlidir:
> **128 + 9 = 137**.
> Kubernetes bu durumu doğrudan `Reason: OOMKilled` olarak etiketler. Bu hata uygulamanın mantıksal bir kod hatasından değil, bellek yetersizliğinden işletim sistemi çekirdeği tarafından öldürüldüğünü gösterir.

### Adım 8: Bellek Sınırlarını Optimize Etme ve Çözüm

`starter/oom-fixed-pod.yaml` dosyasında bellek limiti 128Mi'ye çıkarılmış ve tüketim güvenli seviyeye (20MB) ayarlanmıştır:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: oom-demo
  labels:
    app: oom-demo
spec:
  containers:
  - name: memory-eater
    image: alpine:3.21
    command: ["sh", "-c", "echo 'Bellek ayrildi (guvenli limitlerde)...'; dd if=/dev/zero of=/dev/shm/fill bs=1M count=20; echo 'Pod stabil olarak calisiyor.'; sleep 3600"]
    resources:
      limits:
        memory: "128Mi"
      requests:
        memory: "64Mi"
```

Düzeltilmiş pod'u uygulayın:

```bash
kubectl replace --force -f starter/oom-fixed-pod.yaml -n beginner-troubleshoot
```

Pod'un durumunu gözlemleyin:

```bash
kubectl get pod oom-demo -n beginner-troubleshoot
```

Çıktı:
```
NAME       READY   STATUS    RESTARTS   AGE
oom-demo   1/1     Running   0          10s
```

Logları kontrol edin:

```bash
kubectl logs oom-demo -n beginner-troubleshoot
```

Çıktı:
```
Bellek ayrildi (guvenli limitlerde)...
20+0 records in
20+0 records out
Pod stabil olarak calisiyor.
```

Uygulama artık bellek limitini aşmadığı için `Running` durumunda kesintisiz çalışmaktadır!

---

## Adım 9: Temizlik

Laboratuvarda oluşturduğunuz kaynakları ve namespace'i temizleyin:

```bash
kubectl delete namespace beginner-troubleshoot
```

Namespace silindiğinde içerisindeki tüm podlar otomatik olarak temizlenir.

---

## Özet Sorun Giderme Rehberi

| Hata Durumu | Belirti | Tespit Komutu | Tipik Çözüm |
| :--- | :--- | :--- | :--- |
| **CrashLoopBackOff** | Pod sürekli çöküp yeniden başlıyor | `kubectl logs <pod> --previous` veya `kubectl describe pod <pod>` | Komut, ortam değişkenleri (env), eksik dosya veya uygulama içi hataları düzeltin. |
| **OOMKilled (137)** | `Reason: OOMKilled`, `Exit Code: 137` | `kubectl describe pod <pod>` (Last State altında) | Pod manifestindeki `limits.memory` değerini artırın veya uygulamadaki bellek tüketimini optimize edin. |
| **ImagePullBackOff** | İmaj indirilemiyor | `kubectl describe pod <pod>` | İmaj adını, etiketini (tag) ve private registry için `imagePullSecrets` tanımını kontrol edin. |
| **Pending** | Pod hiçbir node'a atanamıyor | `kubectl describe pod <pod>` (Events bölümü) | Node kaynaklarını (CPU/Memory), `nodeSelector` veya Taints/Tolerations kurallarını kontrol edin. |
