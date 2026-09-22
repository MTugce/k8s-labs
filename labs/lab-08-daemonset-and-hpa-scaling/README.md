# Her Node'da Ajan Çalıştır ve Uygulamanı Otomatik Ölçekle

| Seviye | Tahmini Süre | Profil / Araçlar | Açık Portlar |
| --- | --- | --- | --- |
| Orta | 45 dk | kubectl, Metrics Server | `30087` |

## Amaç

- DaemonSet'in her uygun node'da bir Pod çalıştırdığını görmek.
- CPU request değerine göre HPA'nın Pod sayısını artırıp azaltmasını izlemek.

## Adım Adım Uygulama Rehberi

```bash
kubectl apply -f labs/lab-08-daemonset-and-hpa-scaling/starter/daemonset.yaml
kubectl get daemonset,pods -n private-app -o wide
kubectl apply -f labs/lab-08-daemonset-and-hpa-scaling/starter/hpa.yaml -n private-app
kubectl -n private-app get hpa
kubectl -n private-app run load --rm -it --restart=Never --image=curlimages/curl:8.12.1 -- \
  sh -c 'while true; do curl -s http://devops-app/work?ms=500 >/dev/null; done'
```

Başka terminalde:

```bash
kubectl -n private-app get hpa,pods -w
```

Yükü durdurun ve HPA'nın tekrar `minReplicas` değerine indiğini görün.

## Doğal Doğrulama ve Beklenen Sonuç

DaemonSet sayısı node sayısıyla eşleşir. HPA önce `1`, yük altında daha fazla, yük kesilince tekrar `1` replica gösterir.
