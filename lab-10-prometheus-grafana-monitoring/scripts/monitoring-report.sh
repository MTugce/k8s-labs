#!/usr/bin/env bash
set -euo pipefail

PROMETHEUS_PORT="${PROMETHEUS_PORT:-19090}"
PROMETHEUS_SERVICE="monitoring-kube-prometheus-prometheus"

kubectl -n monitoring port-forward "service/${PROMETHEUS_SERVICE}" "${PROMETHEUS_PORT}:9090" \
  >/tmp/k8s-labs-prometheus-port-forward.log 2>&1 &
port_forward_pid=$!
trap 'kill "$port_forward_pid" 2>/dev/null || true' EXIT
sleep 2

query() {
  local title="$1"
  local expression="$2"
  echo
  echo "== ${title} =="
  curl --fail --silent --show-error --get "http://127.0.0.1:${PROMETHEUS_PORT}/api/v1/query" \
    --data-urlencode "query=${expression}"
  echo
}

query "Prometheus hedefi" 'up{namespace="private-app",service="devops-app"}'
query "İstek hızı" 'sum(rate(devops_app_http_requests_total[1m]))'
query "p95 /work süresi" 'histogram_quantile(0.95, sum(rate(devops_app_http_request_duration_seconds_bucket{route="/work"}[1m])) by (le))'
query "HPA replica sayısı" 'kube_horizontalpodautoscaler_status_current_replicas{namespace="private-app",horizontalpodautoscaler="devops-app"}'
query "Devops App firing alertleri" 'ALERTS{alertstate="firing",alertname=~"DevopsApp.*"}'
