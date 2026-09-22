# Kubectl ve Kind Hızlı Başvuru

Bu sayfa açıklama yerine komut hatırlatıcıdır. Komutu çalıştırmadan önce doğru namespace'i ve nesne adını kontrol edin.

## Kind kümesi

```bash
kind get clusters
kind create cluster --config platform/kind-cluster.yaml
kubectl config use-context kind-k8s-labs
kind get nodes --name k8s-labs
kind delete cluster --name k8s-labs
```

## Küme ve namespace

```bash
kubectl get nodes -o wide
kubectl get namespaces
kubectl create namespace NAME
kubectl get all -n NAME
kubectl delete namespace NAME
```

## Pod işlemleri

```bash
kubectl run NAME --image=IMAGE
kubectl get pods -A
kubectl describe pod NAME -n NAME_SPACE
kubectl logs NAME -n NAME_SPACE
kubectl logs -f NAME -n NAME_SPACE
kubectl exec -it NAME -n NAME_SPACE -- sh
kubectl delete pod NAME -n NAME_SPACE
```

## Deployment ve rollout

```bash
kubectl create deployment NAME --image=IMAGE -n NAME_SPACE
kubectl scale deployment/NAME --replicas=3 -n NAME_SPACE
kubectl set image deployment/NAME CONTAINER=IMAGE -n NAME_SPACE
kubectl rollout status deployment/NAME -n NAME_SPACE
kubectl rollout history deployment/NAME -n NAME_SPACE
kubectl rollout undo deployment/NAME -n NAME_SPACE
kubectl get deploy,rs,pods -n NAME_SPACE
```

## Service ve erişim testi

```bash
kubectl expose deployment NAME --name=NAME-svc --port=80 -n NAME_SPACE
kubectl get svc -n NAME_SPACE
kubectl get endpoints -n NAME_SPACE
kubectl -n NAME_SPACE run curl --rm -it --restart=Never \
  --image=curlimages/curl:8.12.1 -- curl -s SERVICE/healthz
curl http://SUNUCU_IP:30086
curl -H 'Host: student01-app1.devopsatolyesi.com' http://SUNUCU_IP:19001/healthz
```

## ConfigMap, Secret ve private image

```bash
kubectl create configmap NAME --from-literal=KEY=VALUE -n NAME_SPACE
kubectl create secret generic NAME --from-literal=KEY="$VALUE" -n NAME_SPACE
kubectl create secret docker-registry dockerhub-creds -n NAME_SPACE \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username="$DOCKERHUB_USER" --docker-password="$DOCKERHUB_TOKEN" \
  --docker-email="$DOCKERHUB_EMAIL"
kubectl get secret -n NAME_SPACE
kubectl describe pod POD -n NAME_SPACE
```

`stringData` ile manifest yazıldığında Kubernetes onu `.data` içinde Base64'e çevirir. Base64 şifreleme değildir; gerçek değerleri Git'e koymayın.

## Ingress ve Gateway API

```bash
kubectl get ingress -A
kubectl get gateway,httproute -A
kubectl describe ingress NAME -n NAME_SPACE
kubectl describe httproute NAME -n NAME_SPACE
kubectl get gatewayclass
```

## Storage ve StatefulSet

```bash
kubectl get storageclass
kubectl get pv
kubectl get pvc -A
kubectl describe pvc NAME -n NAME_SPACE
kubectl get statefulset -n NAME_SPACE
kubectl get pod -n NAME_SPACE -o wide
```

## DaemonSet ve HPA

```bash
kubectl get daemonset -A
kubectl get hpa -A
kubectl top nodes
kubectl top pods -n NAME_SPACE
kubectl get hpa,pods -n NAME_SPACE -w
```

## Manifest uygulama ve geri alma

```bash
kubectl apply -f DOSYA.yaml
kubectl diff -f DOSYA.yaml
kubectl delete -f DOSYA.yaml
kubectl get events -n NAME_SPACE --sort-by=.lastTimestamp
```
