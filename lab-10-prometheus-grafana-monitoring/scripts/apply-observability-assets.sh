#!/usr/bin/env bash
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

kubectl apply -f "$LAB_DIR/starter/devops-app-servicemonitor.yaml"
kubectl apply -f "$LAB_DIR/starter/devops-app-dashboard.yaml"
kubectl apply -f "$LAB_DIR/starter/devops-app-operations-dashboard.yaml"
kubectl apply -f "$LAB_DIR/starter/devops-app-alert.yaml"

kubectl -n private-app get servicemonitor,prometheusrule
kubectl -n monitoring get configmap -l grafana_dashboard=1
