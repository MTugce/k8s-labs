# İlk Uygulaman: Pod, Deployment ve Service

| Seviye | Tahmini Süre | Profil / Araçlar | Açık Portlar |
| --- | --- | --- | --- |
| Temel | 45 dk | kubectl | `30086` |

## Amaç

- Pod ile Deployment farkını ve self-healing davranışını görmek.
- ClusterIP, NodePort ve ExternalName Service türlerini denemek.
- `kubectl scale`, `set image` ve `rollout undo` komutlarını kullanmak.

## Adım Adım Uygulama Rehberi

```bash
kubectl create namespace first-app
kubectl -n first-app create deployment web --image=nginx:1.27-alpine --replicas=2
kubectl -n first-app expose deployment web --name=web-clusterip --port=80
kubectl -n first-app scale deployment/web --replicas=3
kubectl -n first-app get deploy,rs,pods
kubectl -n first-app get pod -l app=web -o name | head -1 | xargs kubectl -n first-app delete
kubectl -n first-app rollout status deployment/web
```

`starter/service-types.yaml` dosyasını uygulayın:

```bash
kubectl apply -f labs/lab-02-first-app-pod-deployment-and-services/starter/service-types.yaml
kubectl -n first-app run dns-test --rm -it --restart=Never --image=curlimages/curl:8.12.1 -- curl -s web-clusterip
curl http://SUNUCU_IP:30086
kubectl -n first-app get svc external-docs
```

## Doğal Doğrulama ve Beklenen Sonuç

`web-nodeport` `30086` portunda yanıt verir. `external-docs` DNS alias'tır; LoadBalancer'ın Kind üzerinde `Pending` kalması beklenir ve bu nedenle bu labda zorunlu değildir.
