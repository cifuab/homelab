## Kubernetes Audit SOC KPI

This is a drop-in, step-by-step runbook to reproduce the **business KPIs** we measured:
1) Audit volume + Signal ratio  
2) MTTD / detection latency  
3) Deny baseline vs spike (401/403)  
4) Top actor concentration  
5) Secrets access footprint (blast radius)  
6) Noise reduction / curation impact

---

### 0) Prerequisites (once)

### 0.1 Grafana dashboard variable: `$node`
- Loki streams `node=alloy-audit-*`.

**Dashboard → Settings → Variables → node**
- Type: `Query`
- Data source: `Loki`
- Query:
```shell
  label_values({job="k8s-audit"}, node)
```

### 1) Panels required for KPIs (minimal set)


- High-signal events/sec 
- Signal ratio % 
- Everything else can be measured from existing panels + Explore.

### 1.1 Panel: Total audit events/sec (cluster)

- Viz: Time series
- Title: Audit events/sec (cluster)
Query:

```shell
sum(rate({job="k8s-audit"}[5m])) or vector(0)
```

- Unit: ops/s
- Axis soft max (optional): 30

### 1.2 Panel: High-signal events/sec (cluster)

- Viz: Time series
- Title: High-signal events/sec (cluster)
- Query:

```shell
sum(
  rate(
    {job="k8s-audit"}
    | json stage="stage", verb="verb", res="objectRef.resource", sub="objectRef.subresource"
    | stage="ResponseComplete"
    | (
        sub=~"exec|portforward|attach"
        or (res="secrets" and verb=~"get|list")
        or (res=~"roles|rolebindings|clusterroles|clusterrolebindings" and verb=~"create|update|patch|delete|deletecollection")
        or (res=~"daemonsets|deployments|statefulsets" and verb=~"create|update|patch|delete|deletecollection")
        or (res=~"mutatingwebhookconfigurations|validatingwebhookconfigurations|apiservices|customresourcedefinitions" and verb=~"create|update|patch|delete|deletecollection")
      )
  [5m])
) or vector(0)
```

- Unit: ops/s
- Axis soft max: 0.05 (recommended)

### 1.3 Panel: Signal ratio (high-signal / total)

- Viz: Stat
- Title: Signal ratio (high-signal / total)
- Query:

```shell
100 *
(
  sum(
    rate(
      {job="k8s-audit"}
      | json stage="stage", verb="verb", res="objectRef.resource", sub="objectRef.subresource"
      | stage="ResponseComplete"
      | (
          sub=~"exec|portforward|attach"
          or (res="secrets" and verb=~"get|list")
          or (res=~"roles|rolebindings|clusterroles|clusterrolebindings" and verb=~"create|update|patch|delete|deletecollection")
          or (res=~"daemonsets|deployments|statefulsets" and verb=~"create|update|patch|delete|deletecollection")
          or (res=~"mutatingwebhookconfigurations|validatingwebhookconfigurations|apiservices|customresourcedefinitions" and verb=~"create|update|patch|delete|deletecollection")
        )
    [5m])
  )
  /
  sum(rate({job="k8s-audit"}[5m]))
)
```

- Unit: percent (0-100)
- Thresholds (optional): green <1, yellow 1–6, red >6

### 1.4 Panel: 401/403 deny rate (security-only baseline)

- Viz: Time series
- Title: 401/403 rate (security-only)
- Query (exclude known noisy actor if needed):

```shell
sum(
  rate(
    {job="k8s-audit", node=~"$node"}
    | json stage="stage", code="responseStatus.code", user="user.username"
    | stage="ResponseComplete"
    | code=~"401|403"
    | user !~ "system:serviceaccount:kube-system:daemon-set-controller"
  [5m])
) or vector(0)
```

- Unit: ops/s
- Axis soft max: 0.1

### 1.5 Panel: Top high-risk actors (5m)

- Viz: Table
- Title: Top high-risk actors (5m)
- Query (Instant ON recommended):

```shell
topk(10,
  sum by (user) (
    count_over_time(
      {job="k8s-audit", node=~"$node"}
      | json stage="stage", user="user.username", verb="verb", res="objectRef.resource", sub="objectRef.subresource"
      | stage="ResponseComplete"
      | (
          sub=~"exec|portforward|attach"
          or (res="secrets" and verb=~"get|list")
          or (res=~"roles|rolebindings|clusterroles|clusterrolebindings" and verb=~"create|update|patch|delete|deletecollection")
          or (res=~"daemonsets|deployments|statefulsets" and verb=~"create|update|patch|delete|deletecollection")
          or (res=~"mutatingwebhookconfigurations|validatingwebhookconfigurations|apiservices|customresourcedefinitions" and verb=~"create|update|patch|delete|deletecollection")
        )
      | user !~ "system:kube-controller-manager|system:apiserver|system:kube-scheduler|system:node:.*"
    [5m])
  )
)
```

- Grafana setup for the table:
  - Query options: Instant = ON

- Transformations:
  - Labels to fields (Columns)
  - Organize fields: keep user, Value; rename Value → count_5m 
  - Sort by count_5m desc

### 2) Simulation Runbook v1.0 (generates signal for KPIs)

- Run from your jumpbox. Keep Grafana on Last 15m and refresh 5s.

```shell
# Step 0: namespace + SA
kubectl create ns audit-sim || true
kubectl -n audit-sim create sa intruder || true

# Step 1: RBAC create/patch/delete
kubectl -n audit-sim create role sim-role --verb=get --resource=pods || true
kubectl -n audit-sim create rolebinding sim-rb --role=sim-role --serviceaccount=audit-sim:intruder || true
kubectl -n audit-sim patch role sim-role --type='json' -p='[{"op":"add","path":"/rules/0/verbs/-","value":"list"}]'
kubectl -n audit-sim delete rolebinding sim-rb
kubectl -n audit-sim delete role sim-role

# Step 2: Secret create/patch/delete
kubectl -n audit-sim create secret generic demo-secret --from-literal=token=hello || true
kubectl -n audit-sim patch secret demo-secret -p '{"stringData":{"token":"rotated"}}'
kubectl -n audit-sim delete secret demo-secret

# Step 2.5: force secrets GET/LIST (so it shows up as high-signal)
kubectl -n audit-sim get secrets >/dev/null

# Step 3: Exec
kubectl -n audit-sim run audit-debug --image=busybox:1.36 --restart=Never --command -- sh -c 'sleep 120'
kubectl -n audit-sim wait --for=condition=Ready pod/audit-debug --timeout=60s
kubectl -n audit-sim exec -it audit-debug -- sh -lc 'id; date' >/dev/null
kubectl -n audit-sim delete pod audit-debug

# Step 4: Port-forward (clean)
kubectl -n audit-sim run web --image=nginx --restart=Never
kubectl -n audit-sim expose pod web --port=80
kubectl -n audit-sim wait --for=condition=Ready pod/web --timeout=60s
kubectl -n audit-sim port-forward svc/web 8080:80 &
PF_PID=$!
sleep 8
kill $PF_PID
kubectl -n audit-sim delete svc web
kubectl -n audit-sim delete pod web

# Step 5: 403 Forbidden (kubectl run override for SA)
kubectl -n audit-sim run intruder-curl --rm -i --restart=Never \
  --image=curlimages/curl \
  --overrides='{"spec":{"serviceAccountName":"intruder"}}' \
  -- sh -lc '
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
curl -sk -o /dev/null -w "%{http_code}\n" -H "Authorization: Bearer $TOKEN" \
  https://kubernetes.default.svc/api/v1/namespaces/kube-system/secrets
'
```
- Cleanup:

```shell
kubectl delete ns audit-sim
```
### 3) KPI Measurement Steps
### KPI — Audit volume and signal ratio

- Goal: capture baseline + peak during simulation

- Baseline (quiet)

  - Time range: Last 15m

  - Record:
    - Total audit min/max (e.g., 20.9–21.5 ops/s)
    - High-signal near 0 
    - Signal ratio 0%

- Peak (during sim)

  - Run the simulation

  - Hover the charts and record:
    - Total audit peak 
    - High-signal peak 
    - Signal ratio peak

- Conversions (optional)

  - events/min = ops/s * 60

### KPI — MTTD / detection latency

- Goal: seconds from action → first log line visible

- How

- In terminal, capture T0 (min time):

```shell
date -u +"%Y-%m-%d %H:%M:%S.%3N"
```

- Immediately run a single action (RBAC / secret write / exec / 403).

- In Grafana Explore, find the first matching log line (earliest timestamp after T0 (max time)) and take that as T1.

- Latency = T1 - T0

- Recommended Explore filters 
  - RBAC create role: ns="audit-sim" res="roles" verb="create"
  - Secret create: ns="audit-sim" res="secrets" verb="create"
  - Exec: ns="audit-sim" sub="exec"
  - Deny: code="403"

- Report 
  - p50 (median) and worst observed

### KPI — Deny baseline vs spike (401/403)

- Goal: baseline denies/sec vs peak denies/sec

- Baseline:
  - Time range: Last 5m 
  - Record current value of 401/403 rate (security-only)

- Spike:
  - Run Step 5 (403 intruder)
  - Record the peak value (hover)

- Convert to denies/min if needed: ops/s * 60

### KPI — Top actor concentration

- Goal: “Top actor share of high-risk activity”

- During simulation window, open Top high-risk actors (5m)

- Record counts (e.g., admin=12, intruder=5)

- Compute:

  - Total = sum counts

  - Top1 share = top1/total * 100

### KPI — Secrets access footprint (blast radius)

- Goal: number of namespaces touched, whether cluster-scope secrets access happened

- Run in Explore (Last 15m):

- Namespaces touched (secrets get/list)

```shell
topk(50,
  sum by (ns) (
    count_over_time(
      {job="k8s-audit"}
      | json stage="stage", verb="verb", res="objectRef.resource", ns="objectRef.namespace"
      | stage="ResponseComplete"
      | res="secrets"
      | verb=~"get|list"
    [15m])
  )
)
```
- Count rows = N namespaces

- If ns="" exists → cluster-scope

- Cluster-scope explicit check

```shell
{job="k8s-audit"}
| json stage="stage", verb="verb", res="objectRef.resource", ns="objectRef.namespace", uri="requestURI", user="user.username"
| stage="ResponseComplete"
| res="secrets"
| verb=~"get|list"
| (ns="" or uri=~"^/api/v1/secrets\\??")
| line_format "user={{.user}} verb={{.verb}} ns={{.ns}} uri={{.uri}}"
```
- If no lines, report: “No cluster-wide secrets get/list observed”

### KPI — Noise reduction / curation impact

- Goal: “high-signal is tiny % of total”

- Use KPI `#1’s` Signal ratio %:

  - High-signal % = signal_ratio

  - Noise proxy % = 100 - signal_ratio

- Optionally support with events/min:

  - Total events/min = total_ops_s * 60

  - High-signal events/min = high_signal_ops_s * 60
  