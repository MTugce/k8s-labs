# Beginner Kubernetes Labları

Bu bölüm Kubernetes'e yeni başlayanlar için adım adım hazırlanmıştır. Konular en temel imperative komutlardan başlayarak pattern ve mimarilere doğru sırayla ilerler.

---

## Başlangıç Müfredatı

Aşağıdaki laboratuvarları sırasıyla tamamlayın:

| Sıra | Laboratuvar Rehberi | Öğrenme Hedefi |
|:---:|---|---|
| **B1** | [Imperative kubectl ve İlk Podlar](lab-01-imperative-kubectl-and-pod-basics/README.md) | Tek satırlık `kubectl run` komutları, pod inceleme (`get`, `describe`, `logs`, `exec`), port yönlendirme ve `--dry-run=client -o yaml` ile manifest üretimi |
| **B2** | [Pod Tasarım Kalıpları: Multi-Container, Init ve Sidecar](lab-02-pod-design-patterns-multi-init-sidecar/README.md) | Çoklu konteyner mimarisi, localhost ağ paylaşımı, ön hazırlık (Init Container) ve `emptyDir` ile canlı log toplayıcı (Sidecar) |
| **B3** | [Kendi Kendini Onarma: ReplicaSet ve Deployment](lab-03-replicaset-and-deployment/README.md) | Pod'ların ölümlü doğası, ReplicaSet ile self-healing kanıtı, Deployment oluşturma, ölçekleme (`scale`), güncelleme (`set image`) ve geri alma (`rollout undo`) |
| **B4** | [Ağ, Servisler ve Cluster İçi DNS Keşfi](lab-04-services-and-dns/README.md) | Değişken Pod IP'leri sorunu, ClusterIP servisi, CoreDNS ile servis keşfi, NodePort (30086) ile dış erişim ve mikroservis iletişimi |
| **B5** | [Konfigürasyon, Gizli Değerler ve Uygulama Yönetimi](lab-05-configmap-secret-and-application/README.md) | ConfigMap ve Secret oluşturma, `devops-app` uygulamasına bağlama, canlı `/config` testi, Public ve Private imaj ayrımı ile `imagePullSecrets` |
| **B6** | [Temel Depolama: emptyDir, PV ve Dynamic PVC](lab-06-storage-emptydir-and-pvc/README.md) | Geçici disk (`emptyDir`), kalıcı disk (PV/PVC) ilişkisi, dinamik disk talebi ve Pod silinse dahi verinin korunduğunun kanıtı |
| **B7** | [Durumlu Uygulamalar: StatefulSet ve Veritabanı](lab-07-statefulset-and-database/README.md) | StatefulSet mimarisi, Headless Service (`clusterIP: None`), kararlı ağ kimlikleri (`pod-0.service`), `volumeClaimTemplates` ile pod başına özel PVC tahsisi ve MySQL veri kalıcılığı |
| **B8** | [Pod Sorun Giderme: CrashLoopBackOff ve OOMKilled](lab-08-pod-troubleshooting-crashloop-oom/README.md) | En yaygın pod arızalarını teşhis etme, `kubectl logs --previous` ile çökme loglarını okuma, `Exit Code 137` (cgroups OOM Killer) tespiti ve kaynak optimizasyonu |
| **B9** | [Uçtan Uca Mikroservis Dağıtımı (Capstone Projesi)](lab-09-capstone-project/README.md) | Docker Hub Private/Public imaj çekme, `imagePullSecrets`, ConfigMap, Secret, PVC'li MySQL StatefulSet ve NodePort (30088) ile tam entegre bitiş projesi |


---

## Kapsamlı ve İleri Başlangıç Çalışmaları (Ek Referans)

Temel müfredatı tamamladıktan sonra derinlemesine cluster yaşam döngüsü ve context pratikleri için aşağıdaki çalışmaları inceleyebilirsiniz:

- [Kind Cluster, Context, Kubeconfig, Namespace ve Label](lab-01-cluster-kubectl-namespace-labels/README.md)
- [Pod, Deployment, Service ve DNS (Bütünleşik Lab)](lab-02-pod-deployment-service/README.md)
- [ConfigMap, Secret ve Private Registry (Genişletilmiş Lab)](lab-03-configmap-secret-private-image/README.md)
- [PV, PVC ve Static/Dynamic Storage (Genişletilmiş Lab)](lab-04-pv-pvc-storage/README.md)

---

[Ana sayfaya dön](../README.md)
