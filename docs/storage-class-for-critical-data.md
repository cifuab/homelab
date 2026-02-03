### Step 0 — Create a “Retain” StorageClass for critical data (recommended)

### Use this for Grafana + Postgres going forward.

```yaml
# longhorn-retain-sc.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-retain
provisioner: driver.longhorn.io
reclaimPolicy: Retain
volumeBindingMode: Immediate
allowVolumeExpansion: true
parameters:
  numberOfReplicas: "2"          # 2 nodes => 2 replicas (best practice)
  staleReplicaTimeout: "30"
  fsType: "ext4"
```


- Apply:

```shell
kubectl apply -f longhorn-retain-sc.yaml
```


- Verify:

```yaml
kubectl get storageclass
```

### Step 1 — Example: Postgres (Factory-Edge style) with StatefulSet + PVC

### This is the canonical pattern for DBs.

### 1A) Namespace (optional)
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: factory-edge
```

### 1B) Secret for DB password (best practice)
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: pg-secret
  namespace: factory-edge
type: Opaque
stringData:
  POSTGRES_PASSWORD: "change-me"
```

### 1C) StatefulSet with volumeClaimTemplates (creates PVC automatically)
### This matches data-factory-edge-db-0 pattern.

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: factory-edge-db
  namespace: factory-edge
spec:
  serviceName: factory-edge-db
  replicas: 1
  selector:
    matchLabels:
      app: factory-edge-db
  template:
    metadata:
      labels:
        app: factory-edge-db
    spec:
      terminationGracePeriodSeconds: 30
      containers:
        - name: postgres
          image: postgres:16
          ports:
            - containerPort: 5432
              name: pg
          env:
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: pg-secret
                  key: POSTGRES_PASSWORD
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/data
          # (optional) probes for stability
          readinessProbe:
            tcpSocket:
              port: 5432
            initialDelaySeconds: 10
            periodSeconds: 5
          livenessProbe:
            tcpSocket:
              port: 5432
            initialDelaySeconds: 30
            periodSeconds: 10

  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: longhorn-retain
        resources:
          requests:
            storage: 10Gi
```

- What this creates (mapping)

- When you apply this StatefulSet:
  - Kubernetes creates PVC: data-factory-edge-db-0 
  - Longhorn provisions PV: pvc-xxxxx 
  - Longhorn creates volume: pvc-xxxxx (actual disk data)
  - Pod mounts it at /var/lib/postgresql/data

- Apply:

```yaml
kubectl apply -f factory-edge-postgres.yaml
```


- Check mapping:

```shell
kubectl -n factory-edge get pod,pvc
kubectl get pv | grep factory-edge
kubectl -n longhorn-system get volumes.longhorn.io | grep pvc-
```

### Step 2 — Example: Grafana with Deployment + explicit PVC

- Grafana is often deployed as a Deployment with a single PVC.

### 2A) Namespace (optional)
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
```

### 2B) PVC first (explicit)
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: grafana-data
  namespace: monitoring
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn-retain
  resources:
    requests:
      storage: 10Gi
```

### 2C) Deployment that mounts the PVC
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: grafana
  template:
    metadata:
      labels:
        app: grafana
    spec:
      containers:
        - name: grafana
          image: grafana/grafana:11.1.0
          ports:
            - containerPort: 3000
              name: http
          volumeMounts:
            - name: grafana-storage
              mountPath: /var/lib/grafana
      volumes:
        - name: grafana-storage
          persistentVolumeClaim:
            claimName: grafana-data
```


- Apply:

```shell
kubectl apply -f grafana-pvc.yaml
kubectl apply -f grafana-deploy.yaml
```


- Check mapping:

```shell
kubectl -n monitoring get pod,pvc
kubectl get pv | grep grafana
kubectl -n longhorn-system get volumes.longhorn.io | grep pvc-
```

### Step 3 — Best practice scheduling for resilience (2 nodes)

- You want the pod to be able to move if a node dies, and replicas to spread.

### 3A) Add Pod anti-affinity (good practice)

- This prevents multiple replicas of the same app landing on the same node (mainly useful when replicas > 1).

- Add under `spec.template.spec`:

```yaml
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchLabels:
              app: grafana
          topologyKey: kubernetes.io/hostname

```
### 3B) Longhorn replicas

- With 2 Longhorn nodes, use 2 replicas.
- That’s why numberOfReplicas: "2" is in the StorageClass.

### Step 4 — Protect existing PVCs (Grafana/Postgres)

Even if you start using `longhorn-retain`, your existing PVs might still be `Delete`.

- Example For current two PVs:

```shell
kubectl patch pv pvc-8a3ca417-8d7d-4d90-98f6-ca1505818374 \
  -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'

kubectl patch pv pvc-728a3c98-e37f-481d-8df8-46db3a3de900 \
  -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
```

- How you don’t lose data (rule of thumb)
  - Deleting Pods is safe: pod comes back, mounts same PVC. 
  - Deleting Deployments/StatefulSets is usually safe if PVCs remain. 
  - Deleting PVCs is the dangerous operation. 
    - With `Delete` reclaimPolicy ⇒ data wiped. 
    - With `Retain` reclaimPolicy ⇒ data stays and can be recovered.


### A) How to confirm data survives pod delete/restart (what you asked)

- Persistence across pod restarts is guaranteed if:
  - Pod mounts a PVC 
  - PVC is Bound 
  - The new pod mounts the same claim name

### 1) Verify the pod is actually using a PVC
```shell
kubectl -n monitoring get pod -o jsonpath='{range .items[*]}{.metadata.name}{" => "}{range .spec.volumes[*]}{.persistentVolumeClaim.claimName}{" "}{end}{"\n"}{end}'
```

### 2) Verify the PVC is Bound and points to a PV
```shell
kubectl -n monitoring get pvc
kubectl -n monitoring get pvc <pvc-name> -o wide
```


- Look for:
  - STATUS: Bound 
  - VOLUME: pvc-xxxx...

### 3) Prove it by writing a file and restarting the pod

- Example (Grafana typically mounts `/var/lib/grafana`):

```shell
# pick the grafana pod name
kubectl -n monitoring get pod -o name

# write a marker file
kubectl -n monitoring exec -it <grafana-pod> -- sh -lc 'date > /var/lib/grafana/PERSIST_TEST && cat /var/lib/grafana/PERSIST_TEST'

# delete pod (it will be recreated)
kubectl -n monitoring delete pod <grafana-pod>

# wait until Running again, then read the file
kubectl -n monitoring get pod -w
kubectl -n monitoring exec -it <new-grafana-pod> -- sh -lc 'cat /var/lib/grafana/PERSIST_TEST'
```
- If the file is still there → your PVC is persisting across pod restarts.

- Same idea for Postgres (path differs depending on chart).

### B) How to confirm data is “retained” if someone deletes the PVC

- This is where your StorageClass output matters.

- Right now:
  - longhorn reclaimPolicy = Delete 
  - longhorn-static reclaimPolicy = Delete

- That means: if you delete the PVC, data will be deleted (unless you change the PV reclaim policy).

### 1) Check the PV reclaim policy for the actual volumes backing Grafana/Postgres

- This is the source of truth:

```shell
# Grafana PV (replace with your actual PV name)
kubectl get pv <pv-name> -o jsonpath='{.spec.persistentVolumeReclaimPolicy}{"\n"}'

# Postgres PV
kubectl get pv <pv-name> -o jsonpath='{.spec.persistentVolumeReclaimPolicy}{"\n"}'
```
- If it prints `Retain` ✅ data will survive PVC deletion (PV becomes Released)
- If it prints `Delete` ❌ deleting PVC will delete data

### 2) Recommended best practice

- For Grafana + Postgres:
  - either create a StorageClass longhorn-retain for future PVCs 
  - and/or patch existing PVs to Retain

- Example patch (safe, no downtime):

```shell
kubectl patch pv <pv-name> -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
```
- Quick takeaway 
  - Pods deleted/restarted: PVC data persists ✅ (no reclaimPolicy involved)
  - PVC deleted: reclaimPolicy decides whether data is deleted ❗
