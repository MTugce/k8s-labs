{{/* Chart adını veya nameOverride değerini döndürür. */}}
{{- define "devops-app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Release ile chart adını birleştirerek kaynakların tam adını üretir. */}}
{{- define "devops-app.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/* Helm ve Kubernetes tarafından önerilen ortak etiketler. */}}
{{- define "devops-app.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{ include "devops-app.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}

{{/* Deployment selector ve Pod template üzerinde değişmeden kalan etiketler. */}}
{{- define "devops-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "devops-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
