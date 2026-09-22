#!/usr/bin/env bash
set -euo pipefail

kubectl -n private-app delete pod monitoring-load --ignore-not-found
kubectl -n private-app run monitoring-load --restart=Never \
  --image=curlimages/curl:8.12.1 -- \
  sh -c 'while true; do curl -s http://devops-app/work?ms=500 >/dev/null; done'
