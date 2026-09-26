# Node Scheduling ve Bakım

> **Seviye:** Advanced
> **Tahmini süre:** 50–65 dakika
> **Eğitim durumu:** İsteğe bağlı

## Amaç

Bu labda Pod'ları node label ve `nodeSelector` ile belirli bir node'a yerleştirecek, taint/toleration davranışını görecek ve bir worker node'u `cordon`, `drain`, `uncordon` komutlarıyla bakıma alacaksınız.

## Çalışma dizini

```bash
cd ~/k8s-labs/advanced/lab-07-scheduling-and-node-maintenance
```

## 1. Node'ları incele ve hedef worker'ı seç

```bash
kubectl get nodes -o wide
export TARGET_NODE="$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].metadata.name}')"
echo "$TARGET_NODE"
```

Beklenen sonuç: `k8s-labs-worker` veya `k8s-labs-worker2` gibi bir worker node adı görünür.

Değişken boşsa bu labı çalıştırmayın; cluster'da worker node yoktur.

## 2. Node'a label ekle

```bash
kubectl label node "$TARGET_NODE" training-workload=true --overwrite
kubectl get nodes -L training-workload
```

Hedef node'un `TRAINING-WORKLOAD` sütununda `true` görünmelidir.

## 3. nodeSelector ile Pod yerleştir

```bash
kubectl apply -f starter/node-selector.yaml
kubectl rollout status deployment/selected-app -n scheduling-lab --timeout=120s
kubectl get pods -n scheduling-lab -o wide
```

Beklenen sonuç: İki Pod da label eklediğiniz `$TARGET_NODE` üzerinde çalışır.

Deployment içindeki seçim kuralını görüntüleyin:

```bash
kubectl get deployment selected-app -n scheduling-lab \
  -o jsonpath='{.spec.template.spec.nodeSelector}{"\n"}'
```

## 4. NoSchedule taint davranışını gör

Hedef node'a taint ekleyin:

```bash
kubectl taint node "$TARGET_NODE" dedicated=training:NoSchedule
kubectl describe node "$TARGET_NODE" | grep -A2 Taints
```

`NoSchedule` mevcut Pod'ları silmez; yalnızca toleration taşımayan yeni Pod'ların node'a yerleşmesini engeller.

Mevcut Deployment'ı üç Pod'a ölçekleyin:

```bash
kubectl scale deployment selected-app -n scheduling-lab --replicas=3
kubectl get pods -n scheduling-lab -o wide
```

Beklenen sonuç: Yeni Pod `Pending` durumunda kalır. Nedeni inceleyin:

```bash
export PENDING_POD="$(kubectl get pods -n scheduling-lab --field-selector=status.phase=Pending -o jsonpath='{.items[0].metadata.name}')"
kubectl describe pod "$PENDING_POD" -n scheduling-lab
```

Events bölümünde node taint'inin tolere edilmediği mesajı görünür.

## 5. Toleration kullanan uygulamayı çalıştır

```bash
kubectl apply -f starter/toleration.yaml
kubectl rollout status deployment/tolerated-app -n scheduling-lab --timeout=120s
kubectl get pods -n scheduling-lab -o wide
```

Beklenen sonuç: `tolerated-app` Pod'u taint bulunan `$TARGET_NODE` üzerinde çalışır.

## 6. Taint'i kaldır ve Pending Pod'u doğrula

```bash
kubectl taint node "$TARGET_NODE" dedicated=training:NoSchedule-
kubectl wait -n scheduling-lab --for=condition=Ready pod -l app=selected-app --timeout=120s
kubectl get pods -n scheduling-lab -o wide
```

Taint kaldırılınca bekleyen üçüncü Pod da hedef node'a yerleşir.

## 7. Node'u bakıma al

Önce yeni Pod yerleşimini durdurun:

```bash
kubectl cordon "$TARGET_NODE"
kubectl get node "$TARGET_NODE"
```

Node `Ready,SchedulingDisabled` durumuna geçer.

Şimdi workload Pod'larını diğer node'lara taşıyın:

```bash
kubectl drain "$TARGET_NODE" --ignore-daemonsets --delete-emptydir-data
kubectl get pods -A -o wide --field-selector spec.nodeName="$TARGET_NODE"
```

Bu labdaki Deployment `nodeSelector` ile yalnızca bakım node'unu seçtiği için yeniden oluşturulan Pod'lar `Pending` kalabilir. Bu beklenen davranıştır.

Node'u tekrar zamanlamaya açın:

```bash
kubectl uncordon "$TARGET_NODE"
kubectl wait -n scheduling-lab --for=condition=Ready pod -l app=selected-app --timeout=120s
kubectl get pods -n scheduling-lab -o wide
```

## Başarı kriterleri

- Bir worker node'a label ekleyebiliyorsunuz.
- `nodeSelector` ile Pod'u seçilen node'a yerleştirebiliyorsunuz.
- Taint nedeniyle oluşan `Pending` durumunu Events üzerinden açıklayabiliyorsunuz.
- Toleration taşıyan Pod'un taint bulunan node'a yerleştiğini doğrulayabiliyorsunuz.
- Node'u güvenli biçimde cordon, drain ve uncordon yapabiliyorsunuz.

## Temizlik

Önce node'un schedulable ve taint'siz olduğundan emin olun:

```bash
kubectl uncordon "$TARGET_NODE" 2>/dev/null || true
kubectl taint node "$TARGET_NODE" dedicated=training:NoSchedule- 2>/dev/null || true
kubectl label node "$TARGET_NODE" training-workload-
kubectl delete namespace scheduling-lab
```
