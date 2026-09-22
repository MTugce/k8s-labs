#!/usr/bin/env bash
set -euo pipefail

kubectl -n private-app delete pod monitoring-load --ignore-not-found
