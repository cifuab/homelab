### create a longhorn-retain StorageClass and use it

```yaml
Step 1 — Create Retain StorageClass
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-retain
provisioner: driver.longhorn.io
reclaimPolicy: Retain
volumeBindingMode: Immediate
allowVolumeExpansion: true
parameters:
  numberOfReplicas: "2"   # 2 Longhorn nodes => 2 replicas
  fsType: "ext4"
```

```shell
kubectl apply -f longhorn-retain-sc.yaml
kubectl get storageclass
```

### Enable persistence in kube-prometheus-stack (Helm upgrade)

- Create/modify `kps-values-persistence.yaml`:
```yaml
prometheus:
  prometheusSpec:
    retention: 15d
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: longhorn-retain
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 30Gi

alertmanager:
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: longhorn-retain
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 5Gi

grafana:
  persistence:
    enabled: true
    type: pvc
    storageClassName: longhorn-retain
    accessModes:
      - ReadWriteOnce
    size: 10Gi
```

- Then upgrade (keep your existing release name kps and namespace monitoring):

```shell
helm upgrade kps prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f kps-values-persistence.yaml
```

### Verify PVCs now exist
```shell
kubectl -n monitoring get pvc | egrep -i 'prometheus|alertmanager|grafana'
```


- PVCs are created for:
  - Prometheus (...prometheus-0)
  - Alertmanager (...alertmanager-0)
  - Grafana (...grafana)
  - …and they’ll be Bound.

### Quick “important PVC audit” command

- This lists every PVC and its PV reclaim policy:
```shell
kubectl get pvc -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.volumeName}{"\n"}{end}' \
| while read ns pvc pv; do
  rp=$(kubectl get pv "$pv" -o jsonpath='{.spec.persistentVolumeReclaimPolicy}')
  sc=$(kubectl -n "$ns" get pvc "$pvc" -o jsonpath='{.spec.storageClassName}')
  echo -e "$ns\t$pvc\t$sc\t$pv\t$rp"
done
```