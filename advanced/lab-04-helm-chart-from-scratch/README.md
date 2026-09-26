# Sıfırdan Helm Chart Geliştirme ve Release Yaşam Döngüsü

> **Seviye:** Advanced

## Amaç

Bu labda `devops-app` uygulaması için hazır bir chart kullanılmadan sıfırdan Helm chart oluşturulur. Chart şablonları yazılır, public Docker Hub image'ı Kind cluster'a dağıtılır ve release yaşam döngüsünün tamamı uygulanır.

Lab sonunda aşağıdaki işlemleri gerçekleştirebileceksiniz:

- Chart, release, revision ve repository kavramlarını ayırt etmek
- `Chart.yaml`, `values.yaml`, `values.schema.json` ve `templates/` yapısını oluşturmak
- Go template ifadeleri ve `_helpers.tpl` yardımcılarını kullanmak
- Chart'ı `lint`, `template` ve dry-run ile doğrulamak
- Release kurmak, incelemek, güncellemek ve önceki revizyona döndürmek
- Helm testi çalıştırmak, chart paketi üretmek ve release'i kaldırmak

Bu lab başka bir labın Kubernetes kaynaklarını kullanmaz. Uygulama kaynak kodu `app/` dizininde bulunur; Docker Hub image'ı mevcut değilse aynı kaynak kodundan yeniden oluşturulabilir. Bütün Kubernetes kaynakları `helm-chart-lab` namespace'inde oluşturulur.

## Helm Çalışma Modeli

Helm, Kubernetes manifestlerini parametreli ve sürümlenebilir paketler halinde yönetir. Bu paketlere **chart**, chart'ın cluster'a kurulmuş örneğine **release**, release üzerinde yapılan her değişikliğin kayıt numarasına **revision** adı verilir.

```text
GitLab repository                         Docker Hub
└── Helm chart                            └── <kullanıcı>/devops-app-pub:1.0.0
    ├── Chart.yaml                                      │
    ├── values.yaml                                     │ image pull
    └── templates/                                      ▼
            │ helm template/install          Kind: k8s-labs
            ▼                               └── namespace: helm-chart-lab
    Kubernetes manifestleri                    ├── Deployment
                                               ├── ConfigMap
                                               ├── Service
                                               └── Helm test Pod'u
```

Container registry ile chart repository aynı şey değildir:

- **Docker Hub repository**, uygulamanın container image'larını tutar.
- **GitLab repository**, bu labdaki chart kaynak kodunu tutar.
- **Helm repository veya OCI registry**, paketlenmiş chart'ları dağıtmak için kullanılabilir; bu labda chart yerel `.tgz` paketi olarak üretilecektir.

### Chart dizininin temel parçaları

| Yol | Görevi |
|---|---|
| `Chart.yaml` | Chart adı, chart sürümü ve uygulama sürümü gibi metadata değerlerini tanımlar. |
| `values.yaml` | Template'lerin kullandığı varsayılan değerleri tutar. |
| `values.schema.json` | Girilen values değerlerinin tipini ve kabul edilen aralığını doğrular. |
| `templates/` | Kubernetes manifestlerine dönüştürülen Go template dosyalarını içerir. |
| `templates/_helpers.tpl` | Tekrar kullanılan ad ve label şablonlarını tanımlar. Kendi başına manifest üretmez. |
| `templates/NOTES.txt` | Kurulum tamamlandıktan sonra gösterilen kullanım bilgisini üretir. |
| `templates/tests/` | `helm test` tarafından çalıştırılan test kaynaklarını içerir. |
| `.helmignore` | Chart paketi dışında bırakılacak dosyaları belirtir. |

### Values ve template bağlamı

Template içindeki `.` geçerli bağlamı ifade eder. En sık kullanılan kök nesneler şunlardır:

- `.Values`: `values.yaml`, ek values dosyaları ve `--set` seçenekleriyle gelen yapılandırma
- `.Chart`: `Chart.yaml` içeriği
- `.Release`: release adı, namespace ve revision bilgisi
- `.Capabilities`: hedef Kubernetes cluster'ının API yetenekleri

Values önceliği düşükten yükseğe şöyledir:

```text
values.yaml → -f my-values.yaml → --set anahtar=değer
```

Sonraki kaynak daha önce tanımlanan aynı anahtarı geçersiz kılar.

### `version` ve `appVersion` farkı

```yaml
version: 0.1.0
appVersion: "1.0.0"
```

- `version`, Helm chart paketinin sürümüdür. Template veya varsayılan değer değiştiğinde artırılır.
- `appVersion`, chart'ın dağıttığı uygulama sürümünü açıklar. Bilgilendirici metadata değeridir; image tag değerini kendiliğinden değiştirmez.

## Çalışma Dizini ve Değişkenler

Lab dizinine geçin:

```bash
cd ~/k8s-labs/advanced/lab-04-helm-chart-from-scratch
```

Docker Hub kullanıcı adınızı girin. `dockerhub-kullanici-adi` örnek değerini kullanmayın:

```bash
export DOCKERHUB_USERNAME="dockerhub-kullanici-adiniz"
test "$DOCKERHUB_USERNAME" != "dockerhub-kullanici-adiniz"
```

Public image adresi aşağıdaki biçimde olacaktır:

```text
docker.io/<DOCKERHUB_USERNAME>/devops-app-pub:1.0.0
```

Docker Hub'da `devops-app-pub` repository'sinin **Public** olduğunu kontrol edin. Chart veya Kubernetes manifesti içine Docker Hub parolası ya da access token yazmayın.

Doğru Kind cluster'ı kullandığınızı doğrulayın:

```bash
kubectl config use-context kind-k8s-labs
kubectl get nodes
helm version --short
```

Beklenen sonuç: Üç node `Ready` durumunda görünür ve Helm sürümü yazdırılır.

## 1. Uygulama Image'ını Docker Hub'a Gönderme

`app/` dizini bu laba ait bağımsız uygulama kopyasını içerir:

```bash
find app -maxdepth 1 -type f -print
```

Beklenen dosyalar:

```text
app/Dockerfile
app/package.json
app/server.js
```

Docker Hub'a giriş yapın. Parola yerine Docker Hub Personal Access Token kullanabilirsiniz:

```bash
docker login --username "$DOCKERHUB_USERNAME"
```

Uygulamanın `1.0.0` image'ını oluşturup public repository'ye gönderin:

```bash
docker build \
  --build-arg APP_VERSION=1.0.0 \
  --tag "$DOCKERHUB_USERNAME/devops-app-pub:1.0.0" \
  ./app

docker push "$DOCKERHUB_USERNAME/devops-app-pub:1.0.0"
```

Uzak image manifestinin erişilebilir olduğunu doğrulayın:

```bash
docker buildx imagetools inspect \
  "$DOCKERHUB_USERNAME/devops-app-pub:1.0.0"
```

Bu komut Docker Hub'daki manifest digest ve platform bilgilerini göstermelidir. Repository public olduğu için Kind node'larının ayrıca `imagePullSecret` kullanması gerekmez.

## 2. Chart İskeletini Oluşturma

Çalışma alanını oluşturun ve Helm'in başlangıç chart'ını üretin:

```bash
mkdir -p work
helm create work/devops-app
find work/devops-app -maxdepth 2 -type f | sort
```

`helm create`, örnek Deployment, Service, Ingress, ServiceAccount ve test dosyaları üretir. Bu labda her dosya sıfırdan yazılacağı için üretilen template dizinini temizleyin:

```bash
rm -rf work/devops-app/templates
mkdir -p work/devops-app/templates/tests
```

Chart'ın oluşturacağınız son yapısı şöyledir:

```text
work/devops-app/
├── .helmignore
├── Chart.yaml
├── values.schema.json
├── values.yaml
└── templates/
    ├── _helpers.tpl
    ├── configmap.yaml
    ├── deployment.yaml
    ├── service.yaml
    ├── NOTES.txt
    └── tests/
        └── test-connection.yaml
```

## 3. Chart Metadata Dosyasını Yazma

`Chart.yaml` dosyasını oluşturun:

```bash
cat > work/devops-app/Chart.yaml <<'EOF'
apiVersion: v2
name: devops-app
description: Kind üzerinde devops-app dağıtımı için örnek Helm chart
type: application
version: 0.1.0
appVersion: "1.0.0"
kubeVersion: ">=1.25.0-0"
EOF
```

`apiVersion: v2`, Helm 3 ve Helm 4 tarafından desteklenen kararlı chart biçimidir. `type: application`, chart'ın kurulabilir bir uygulama paketi olduğunu belirtir.

## 4. Varsayılan Values Dosyasını Yazma

`values.yaml`, template dosyalarındaki değişkenlerin varsayılan değerlerini tek yerde toplar:

```bash
cat > work/devops-app/values.yaml <<'EOF'
replicaCount: 2

image:
  repository: dockerhub-kullanici-adi/devops-app-pub
  tag: "1.0.0"
  pullPolicy: IfNotPresent

imagePullSecrets: []
nameOverride: ""
fullnameOverride: ""

app:
  message: "Helm ile yonetilen devops-app"

service:
  type: ClusterIP
  port: 80
  targetPort: 8080

resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 250m
    memory: 128Mi

probes:
  liveness:
    path: /healthz
    initialDelaySeconds: 10
    periodSeconds: 10
  readiness:
    path: /healthz
    initialDelaySeconds: 3
    periodSeconds: 5
EOF
```

Varsayılan dosyada gerçek kullanıcı adına bağlı değer bırakmamak için Docker Hub adresini ayrı bir values dosyasında tanımlayın:

```bash
cat > work/my-values.yaml <<EOF
image:
  repository: ${DOCKERHUB_USERNAME}/devops-app-pub
  tag: "1.0.0"

app:
  message: "Docker Hub public image ile Helm kurulumu"
EOF
```

Oluşan dosyayı inceleyin ve kullanıcı adının doğru açıldığını doğrulayın:

```bash
cat work/my-values.yaml
```

## 5. Values Şemasını Eklemek

JSON Schema, hatalı values değerlerinin manifest üretilmeden önce reddedilmesini sağlar:

```bash
cat > work/devops-app/values.schema.json <<'EOF'
{
  "$schema": "https://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["replicaCount", "image", "app", "service"],
  "properties": {
    "replicaCount": {
      "type": "integer",
      "minimum": 1
    },
    "image": {
      "type": "object",
      "required": ["repository", "tag", "pullPolicy"],
      "properties": {
        "repository": { "type": "string", "minLength": 1 },
        "tag": { "type": "string", "minLength": 1 },
        "pullPolicy": {
          "type": "string",
          "enum": ["Always", "IfNotPresent", "Never"]
        }
      }
    },
    "imagePullSecrets": {
      "type": "array"
    },
    "app": {
      "type": "object",
      "required": ["message"],
      "properties": {
        "message": { "type": "string" }
      }
    },
    "service": {
      "type": "object",
      "required": ["type", "port", "targetPort"],
      "properties": {
        "type": {
          "type": "string",
          "enum": ["ClusterIP", "NodePort", "LoadBalancer"]
        },
        "port": { "type": "integer", "minimum": 1, "maximum": 65535 },
        "targetPort": { "type": "integer", "minimum": 1, "maximum": 65535 }
      }
    }
  }
}
EOF
```

Şemanın çalışmasını hatalı bir değerle kontrol edin:

```bash
helm lint work/devops-app --set replicaCount=0
```

Beklenen sonuç: `replicaCount` değerinin `1` veya daha büyük olması gerektiğini belirten hata alınır. Bu hata bilinçli olarak üretilmiştir.

## 6. Ortak İsim ve Label Yardımcılarını Yazma

`_helpers.tpl`, birden fazla manifestte kullanılan template bloklarını merkezi hale getirir:

```bash
cat > work/devops-app/templates/_helpers.tpl <<'EOF'
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
EOF
```

Burada kullanılan önemli fonksiyonlar:

- `default`: Bir değer verilmemişse varsayılanı seçer.
- `include`: İsimlendirilmiş helper template'i çağırır.
- `trunc` ve `trimSuffix`: Kubernetes'in 63 karakterlik DNS label sınırına uygun ad üretir.
- `quote`: Değeri YAML string olarak yazar.
- `nindent`: Çıktıyı yeni satırdan başlayarak istenen sayıda boşlukla girintiler.

## 7. ConfigMap Template'ini Yazma

Uygulama mesajını values üzerinden yöneten ConfigMap'i oluşturun:

```bash
cat > work/devops-app/templates/configmap.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "devops-app.fullname" . }}
  labels:
    {{- include "devops-app.labels" . | nindent 4 }}
data:
  APP_MESSAGE: {{ .Values.app.message | quote }}
EOF
```

`include` sonucu çok satırlı olduğu için `nindent 4` ile `labels` alanının altına doğru seviyede yerleştirilir.

## 8. Deployment Template'ini Yazma

Deployment template'ini oluşturun:

```bash
cat > work/devops-app/templates/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "devops-app.fullname" . }}
  labels:
    {{- include "devops-app.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      {{- include "devops-app.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "devops-app.selectorLabels" . | nindent 8 }}
    spec:
      {{- with .Values.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - name: http
              containerPort: {{ .Values.service.targetPort }}
              protocol: TCP
          env:
            - name: APP_MESSAGE
              valueFrom:
                configMapKeyRef:
                  name: {{ include "devops-app.fullname" . }}
                  key: APP_MESSAGE
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
          livenessProbe:
            httpGet:
              path: {{ .Values.probes.liveness.path }}
              port: http
            initialDelaySeconds: {{ .Values.probes.liveness.initialDelaySeconds }}
            periodSeconds: {{ .Values.probes.liveness.periodSeconds }}
          readinessProbe:
            httpGet:
              path: {{ .Values.probes.readiness.path }}
              port: http
            initialDelaySeconds: {{ .Values.probes.readiness.initialDelaySeconds }}
            periodSeconds: {{ .Values.probes.readiness.periodSeconds }}
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
EOF
```

`with` bloğu, `imagePullSecrets` listesi boşken alanın manifestte hiç üretilmemesini sağlar. `toYaml`, iç içe values nesnesini YAML'a dönüştürür. `POD_NAME`, Kubernetes Downward API üzerinden çalışma zamanında alınır.

## 9. Service Template'ini Yazma

Cluster içi erişim sağlayan Service'i oluşturun:

```bash
cat > work/devops-app/templates/service.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: {{ include "devops-app.fullname" . }}
  labels:
    {{- include "devops-app.labels" . | nindent 4 }}
spec:
  type: {{ .Values.service.type }}
  selector:
    {{- include "devops-app.selectorLabels" . | nindent 4 }}
  ports:
    - name: http
      port: {{ .Values.service.port }}
      targetPort: http
      protocol: TCP
EOF
```

Service selector ile Pod label'ları aynı helper'ı kullanır. Böylece iki dosyanın zaman içinde birbirinden kopması önlenir.

## 10. Kurulum Notu ve Helm Testi Eklemek

Kurulum tamamlandığında gösterilecek komutları `NOTES.txt` içine yazın:

```bash
cat > work/devops-app/templates/NOTES.txt <<'EOF'
Release {{ .Release.Name }} başarıyla kuruldu.

Uygulamaya yerel erişim için:

  kubectl --namespace {{ .Release.Namespace }} port-forward service/{{ include "devops-app.fullname" . }} 18080:{{ .Values.service.port }}

Ardından başka bir terminalde:

  curl http://127.0.0.1:18080/
  curl http://127.0.0.1:18080/healthz
  curl http://127.0.0.1:18080/config
EOF
```

Release kurulduktan sonra Service üzerinden `/healthz` endpoint'ini kontrol edecek test Pod'unu oluşturun:

```bash
cat > work/devops-app/templates/tests/test-connection.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: "{{ include "devops-app.fullname" . }}-test-connection"
  labels:
    {{- include "devops-app.labels" . | nindent 4 }}
  annotations:
    "helm.sh/hook": test
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
spec:
  restartPolicy: Never
  containers:
    - name: wget
      image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
      imagePullPolicy: {{ .Values.image.pullPolicy }}
      command: ["wget"]
      args:
        - "-qO-"
        - "http://{{ include "devops-app.fullname" . }}:{{ .Values.service.port }}/healthz"
EOF
```

`helm.sh/hook: test` annotation'ı bu Pod'un normal kurulum kaynağı değil, Helm test kaynağı olduğunu belirtir.

## 11. Chart'ı Statik Olarak Doğrulama

Önce chart yapısını ve values şemasını denetleyin:

```bash
helm lint work/devops-app --values work/my-values.yaml
```

Beklenen sonuç:

```text
1 chart(s) linted, 0 chart(s) failed
```

Template'leri cluster'a göndermeden düz Kubernetes manifestlerine dönüştürün:

```bash
helm template devops-app work/devops-app \
  --namespace helm-chart-lab \
  --values work/my-values.yaml \
  > work/rendered.yaml

grep '^kind:' work/rendered.yaml
```

Çıktıda `ConfigMap`, `Service`, `Deployment` ve test hook'u olan `Pod` görülmelidir.

Son olarak Helm kurulum isteğini server-side doğrulama yapmadan simüle edin:

```bash
helm install devops-app work/devops-app \
  --namespace helm-chart-lab \
  --create-namespace \
  --values work/my-values.yaml \
  --dry-run \
  --debug
```

Dry-run başarılı olsa bile image'ın gerçekten çekilebildiğini veya Pod'un hazır olacağını garanti etmez. Bunlar gerçek kurulumda doğrulanacaktır.

## 12. Chart'ı Kind Cluster'a Kurma

Chart'ı `devops-app` release adıyla kurun:

```bash
helm install devops-app work/devops-app \
  --namespace helm-chart-lab \
  --create-namespace \
  --values work/my-values.yaml \
  --wait \
  --timeout 3m
```

`--wait`, Deployment hazır olmadan komutun başarılı sayılmasını önler. Kurulumu Helm ve Kubernetes tarafından ayrı ayrı doğrulayın:

```bash
helm list --namespace helm-chart-lab
helm status devops-app --namespace helm-chart-lab
kubectl get all,configmap --namespace helm-chart-lab
kubectl rollout status deployment/devops-app \
  --namespace helm-chart-lab \
  --timeout=120s
```

Beklenen durum:

- Release durumu `deployed` olur.
- İki uygulama Pod'u `Running` ve `Ready` görünür.
- `devops-app` Service ve ConfigMap kaynakları oluşur.

## 13. Uygulamayı Doğrulama

Service'i yalnızca yerel arayüzde erişilebilir hale getirin:

```bash
kubectl port-forward \
  --namespace helm-chart-lab \
  service/devops-app \
  18080:80 \
  --address 127.0.0.1 &
export HELM_PORT_FORWARD_PID=$!
```

Endpoint'leri kontrol edin:

```bash
curl --fail http://127.0.0.1:18080/
curl --fail http://127.0.0.1:18080/healthz
curl --fail http://127.0.0.1:18080/config
```

Beklenen sonuçlarda şunlar bulunur:

```text
"version":"1.0.0"
"status":"UP"
"message":"Docker Hub public image ile Helm kurulumu"
```

İsteklerin farklı Pod'lara gidebildiğini görmek için ana endpoint'i birkaç kez çağırın:

```bash
for request_number in 1 2 3 4 5; do
  curl --silent http://127.0.0.1:18080/
  echo
done
```

## 14. Kurulu Release'i İnceleme

Helm'in kaydettiği values ve oluşturduğu manifestleri görüntüleyin:

```bash
helm get values devops-app \
  --namespace helm-chart-lab \
  --all

helm get manifest devops-app \
  --namespace helm-chart-lab \
  > work/installed-manifest.yaml

helm history devops-app --namespace helm-chart-lab
```

İlk kurulum `REVISION 1` olarak ve `deployed` durumunda görünmelidir.

## 15. Uygulama ve Release Güncelleme

Upgrade sırasında gerçek bir image değişikliği görmek için `1.1.0` image'ını oluşturup aynı public repository'ye gönderin:

```bash
docker build \
  --build-arg APP_VERSION=1.1.0 \
  --tag "$DOCKERHUB_USERNAME/devops-app-pub:1.1.0" \
  ./app

docker push "$DOCKERHUB_USERNAME/devops-app-pub:1.1.0"
```

Chart metadata değerlerini yeni chart ve uygulama sürümüyle güncelleyin:

```bash
cat > work/devops-app/Chart.yaml <<'EOF'
apiVersion: v2
name: devops-app
description: Kind üzerinde devops-app dağıtımı için örnek Helm chart
type: application
version: 0.2.0
appVersion: "1.1.0"
kubeVersion: ">=1.25.0-0"
EOF
```

Release'i yeni image, üç replica ve yeni mesajla güncelleyin:

```bash
helm upgrade devops-app work/devops-app \
  --namespace helm-chart-lab \
  --values work/my-values.yaml \
  --set image.tag=1.1.0 \
  --set replicaCount=3 \
  --set-string app.message="Helm upgrade basarili" \
  --wait \
  --timeout 3m \
  --atomic
```

`--atomic`, upgrade başarısız olursa release'i son çalışan duruma geri alır. Yeni durumu kontrol edin:

```bash
helm history devops-app --namespace helm-chart-lab
kubectl get deployment,pods --namespace helm-chart-lab
curl --fail http://127.0.0.1:18080/
curl --fail http://127.0.0.1:18080/config
```

Beklenen sonuç:

- `REVISION 2` durumu `deployed` olur.
- Deployment üç hazır replica çalıştırır.
- Ana endpoint `version: 1.1.0` döndürür.
- Config endpoint'i `Helm upgrade basarili` mesajını döndürür.

## 16. Önceki Revizyona Dönme

İlk çalışan revizyona geri dönün:

```bash
helm rollback devops-app 1 \
  --namespace helm-chart-lab \
  --wait \
  --timeout 3m
```

Rollback mevcut geçmişi silmez; geri alınan ayarlarla yeni bir revision oluşturur:

```bash
helm history devops-app --namespace helm-chart-lab
kubectl get deployment,pods --namespace helm-chart-lab
curl --fail http://127.0.0.1:18080/
curl --fail http://127.0.0.1:18080/config
```

Beklenen sonuç:

- `REVISION 3` durumu `deployed` olur.
- Replica sayısı yeniden iki olur.
- Uygulama sürümü `1.0.0` ve ilk mesaj yeniden görünür.

## 17. Helm Testini Çalıştırma

Kurulu release için chart içindeki test hook'unu çalıştırın:

```bash
helm test devops-app \
  --namespace helm-chart-lab \
  --logs
```

Beklenen sonuç:

```text
Phase: Succeeded
```

Test başarısız olursa Helm release otomatik olarak silinmez. Test Pod'u, Service ve uygulama logları ayrı ayrı incelenebilir.

## 18. Chart Paketini Oluşturma

Yerel chart'ın son halini tekrar doğrulayın ve paketleyin:

```bash
helm lint work/devops-app --values work/my-values.yaml
helm package work/devops-app --destination work
ls -lh work/devops-app-0.2.0.tgz
```

Paket metadata değerlerini doğrudan arşivden okuyun:

```bash
helm show chart work/devops-app-0.2.0.tgz
helm show values work/devops-app-0.2.0.tgz
```

`.tgz` dosyası bir Helm veya OCI repository'ye yayımlanabilir. Bu labda chart kaynakları GitLab'da, uygulama image'ları Docker Hub'da tutulmaya devam eder.

## 19. Release'i Kaldırma

Önce port-forward işlemini sonlandırın:

```bash
kill "$HELM_PORT_FORWARD_PID" 2>/dev/null || true
unset HELM_PORT_FORWARD_PID
```

Release'i kaldırın:

```bash
helm uninstall devops-app --namespace helm-chart-lab
kubectl delete namespace helm-chart-lab
```

Temizliği doğrulayın:

```bash
helm list --all-namespaces --filter '^devops-app$'
kubectl get namespace helm-chart-lab
```

İlk komut boş liste döndürmeli, ikinci komut namespace'in bulunamadığını belirtmelidir. Docker Hub'daki image'lar ve `work/` içindeki chart kaynakları sonraki çalışmalar için korunur.

## Sorun Giderme

| Belirti | Kontrol | Çözüm |
|---|---|---|
| `ImagePullBackOff` | `kubectl describe pod -n helm-chart-lab POD_ADI` | Docker Hub kullanıcı adını, image tag'ini ve repository'nin public olduğunu kontrol edin. |
| Template parse hatası | `helm template devops-app work/devops-app --debug` | Hata satırındaki `{{ }}` ifadelerini ve girintiyi kontrol edin. |
| Service endpoint üretmiyor | `kubectl get endpointslice -n helm-chart-lab` | Service selector ile Pod label değerlerini karşılaştırın. |
| Pod hazır olmuyor | `kubectl logs -n helm-chart-lab deployment/devops-app` | `/healthz` probe yolunu ve container portunu kontrol edin. |
| Release adı kullanımda | `helm list -A --filter '^devops-app$'` | Mevcut release'i upgrade edin veya kendi namespace'inden kaldırın. |
| Upgrade başarısız | `helm history devops-app -n helm-chart-lab` | `--atomic` son çalışan revizyona döndüyse hatalı values veya image değerini düzeltip yeniden deneyin. |

## Başarı Kriterleri

- Public `devops-app-pub:1.0.0` ve `1.1.0` image'larını Docker Hub'a gönderdiniz.
- Chart dosyalarını hazır chart kopyalamadan oluşturdunuz.
- Values şemasının hatalı girişi reddettiğini gözlemlediniz.
- `helm lint`, `helm template` ve dry-run kontrollerini tamamladınız.
- Release'i Kind cluster'a kurup uygulama endpoint'lerini doğruladınız.
- Release'i yeni image ve values ile upgrade ettiniz.
- Revision geçmişini inceleyip ilk sürüme rollback yaptınız.
- Helm testini başarıyla çalıştırdınız.
- Sürümlü `.tgz` chart paketi oluşturdunuz.
- Release'i ve yalnızca bu laba ait namespace'i kaldırdınız.

Çalışma sırasında oluşturduğunuz chart'ı repository'deki `solution/devops-app/` diziniyle karşılaştırabilirsiniz. Bu dizin başlangıç sürümünün çalışan referansıdır; uygulama adımlarında doğrudan kopyalanmamalıdır.
