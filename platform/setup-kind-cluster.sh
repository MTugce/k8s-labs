#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="k8s-labs"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQUIRED_PORTS=(19001 19002 19003 30086 30087 30088 30089)

for command in docker kind kubectl helm; do
  command -v "$command" >/dev/null || { echo "Eksik araç: $command" >&2; exit 1; }
done

for port in "${REQUIRED_PORTS[@]}"; do
  if ss -ltn "sport = :${port}" | grep -q LISTEN; then
    echo "Port ${port} kullanımda. Mevcut servisi değiştirmeden kurulum durduruldu:" >&2
    ss -ltnp "sport = :${port}" >&2 || true
    exit 1
  fi
done

sudo mkdir -p /opt/k8s-labs/static-pv
sudo chmod 0777 /opt/k8s-labs/static-pv

if kind get clusters | grep -qx "$CLUSTER_NAME"; then
  echo "${CLUSTER_NAME} zaten var; yeniden oluşturulmadı."
else
  kind create cluster --config "$SCRIPT_DIR/kind-cluster.yaml"
fi

kubectl config use-context "kind-${CLUSTER_NAME}"

# Sürümler manifestlere yazılarak uygulanacak; latest kullanılmaz.
kubectl apply -f https://github.com/kubernetes/ingress-nginx/raw/controller-v1.12.0/deploy/static/provider/kind/deploy.yaml
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.7.2/components.yaml
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.36/deploy/local-path-storage.yaml
kubectl -n kube-system patch deployment metrics-server --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

kubectl wait --namespace ingress-nginx --for=condition=Ready pod \
  --selector=app.kubernetes.io/component=controller --timeout=180s
kubectl wait --namespace kube-system --for=condition=Available deployment/metrics-server --timeout=180s
kubectl wait --namespace local-path-storage --for=condition=Available deployment/local-path-provisioner --timeout=180s

echo "Hazır: app1=19001, app2=19002, app3=19003; NodePort=30086-30089"
