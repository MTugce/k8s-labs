# * Namespace Kaynak Sınırı Koy: LimitRange ve ResourceQuota

## Amaç

LimitRange ve ResourceQuota ile bir namespace'in kaynak tüketimini sınırlandırmak.

## Çalışma dizini

```bash
cd ~/k8s-labs/lab-11-limitrange-resourcequota
```

## * Doğrulanan senaryo

LimitRange varsayılan kaynak değerlerini ekledi. Quota altında normal Deployment
çalıştı; beş replica isteyen Deployment ise Pod/CPU kotası nedeniyle tamamlanamadı.

## 1. Namespace, LimitRange ve ResourceQuota uygula

```bash
kubectl apply -f ~/k8s-labs/lab-11-limitrange-resourcequota/starter/governance.yaml
kubectl -n governance-lab get limitrange,resourcequota
kubectl -n governance-lab describe limitrange lab-defaults
kubectl -n governance-lab describe resourcequota lab-quota
```

Beklenen sonuç: LimitRange varsayılan request/limit değerlerini, ResourceQuota ise en fazla dört Pod kuralını gösterir.

## 2. Kaynak belirtmeyen normal Deployment oluştur

Bu manifestte container resources alanı yoktur. LimitRange otomatik değer ekler.

```bash
kubectl apply -f ~/k8s-labs/lab-11-limitrange-resourcequota/starter/allowed-deployment.yaml
kubectl -n governance-lab rollout status deployment/allowed-app
kubectl -n governance-lab get pods
kubectl -n governance-lab describe pod -l app=allowed-app
```

Beklenen sonuç: Pod çalışır. `describe` çıktısında Resources bölümünde LimitRange'in eklediği CPU ve memory request/limit değerleri görünür.

## 3. Quota'yı aşan Deployment'ı dene

Bu manifest beş replica ister; namespace için izin verilen Pod sayısı dörttür.

```bash
kubectl apply -f ~/k8s-labs/lab-11-limitrange-resourcequota/starter/rejected-deployment.yaml
kubectl -n governance-lab get deployment,replicaset,pods
kubectl -n governance-lab describe replicaset -l app=rejected-app
```

Beklenen sonuç: Deployment ve ReplicaSet oluşturulur; quota'da kalan boşluk kadar Pod oluşabilir fakat istenen beş replica tamamlanamaz. Events bölümünde `exceeded quota` veya `forbidden` mesajı görünür.

## 4. Kullanılan bütçeyi incele

```bash
kubectl -n governance-lab describe resourcequota lab-quota
```

Beklenen sonuç: `Used` ve `Hard` değerlerini karşılaştırırsın. Bu labda quota'nın uygulamayı sonradan değil, Pod oluşturulurken koruduğunu gördün.
