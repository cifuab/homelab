### Observability Setup (Talos + Cilium + Hubble + Prometheus + Grafana)
![img](../img/cilium-dashboard.gif)

**Goal:** End-to-end observability for Cilium/Hubble:
- Enable **Hubble metrics** + Cilium/Operator metrics
- Install **kube-prometheus-stack** (Prometheus Operator + Grafana)
- Ensure **ServiceMonitors** are actually scraped
- Build a clean **Grafana dashboard** (Hubble + Cilium “enterprise” panels)
- Include **all queries used** (PromQL)

> This document assumes Cilium is already installed and running on all nodes.

---
```yaml
prometheus:
  prometheusSpec:
    serviceMonitorNamespaceSelector: {}
    serviceMonitorSelector: {}

    podMonitorNamespaceSelector: {}
    podMonitorSelector: {}
```
### 0) Baseline checks (before touching observability)
### Confirm Cilium + Hubble are running
```bash
kubectl -n kube-system get pods -l k8s-app=cilium -o wide
kubectl -n kube-system get pods | grep -E "hubble|cilium|operator"
kubectl -n kube-system exec ds/cilium -- cilium status | sed -n '1,120p'
```
---

### 1) Enable Hubble + Cilium Prometheus metrics (Helm values)
### 1.1 Update your cilium-values.yaml

- Add (or confirm) these sections.

>  - If you already had hubble enabled, the important part is: `hubble.metrics.enabled` list (otherwise metrics stay disabled).

```yaml
# --- Metrics (Prometheus) ---

# Cilium agent metrics
prometheus:
  enabled: true
  serviceMonitor:
    enabled: true   # requires Prometheus Operator (kube-prometheus-stack)

# Cilium operator metrics
operator:
  prometheus:
    enabled: true
    serviceMonitor:
      enabled: true # requires Prometheus Operator

# Hubble metrics
hubble:
  enabled: true
  relay:
    enabled: true
  ui:
    enabled: true

  metrics:
    enabled:
      - dns:query;ignoreAAAA
      - drop
      - tcp
      - flow
    serviceMonitor:
      enabled: true # requires Prometheus Operator

  # Hubble Relay metrics (optional, but nice)
  relay:
    prometheus:
      enabled: true
      serviceMonitor:
        enabled: true # requires Prometheus Operator
```

### 1.2 Apply upgrade
```shell
helm upgrade --install cilium cilium/cilium -n kube-system -f cilium-values.yaml
kubectl -n kube-system rollout status ds/cilium
kubectl -n kube-system rollout status deploy/cilium-operator
kubectl -n kube-system rollout status deploy/hubble-relay
```

### 1.3 Verify Hubble metrics service exists
```shell
kubectl -n kube-system get svc | grep -E "hubble|cilium|operator"
```


- Expected (example):
  - `hubble-metrics` (headless) port `9965`
  - `cilium-agent` metrics (typically `9962`) via Service/Endpoints

---

### 2) Prove metrics are emitted (without Prometheus)

- This validates /metrics is live.

### 2.1 Port-forward Hubble metrics locally (from jumpbox)
```shell
kubectl -n kube-system port-forward svc/hubble-metrics 9965:9965
```

### 2.2 Read metrics (new terminal)
```shell
curl -s http://127.0.0.1:9965/metrics | head -n 40
curl -s http://127.0.0.1:9965/metrics | grep -E '^hubble_' | head -n 40
```


- Stop port-forward with Ctrl+C when done. Prometheus does not need port-forward.

---

### 3) Install kube-prometheus-stack (Prometheus Operator and Grafana)
### 3.1 Install
```shell
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install kps prometheus-community/kube-prometheus-stack -n monitoring
```

### 3.2 Verify components
```shell
kubectl -n monitoring get pods
kubectl -n monitoring get prometheus
kubectl -n monitoring get svc | grep -i prometheus
kubectl -n monitoring get svc | grep -i grafana
```


- Expected key items:
  - `prometheus-kps-kube-prometheus-stack-prometheus-0` Running 
  - `kps-grafana` Service exists

---

#### 4) Ensure ServiceMonitors are present (Cilium/Hubble)
#### 4.1 Check ServiceMonitor CRD exists
````shell
kubectl get crd servicemonitors.monitoring.coreos.com
````

#### 4.2 Check Cilium/Hubble ServiceMonitors exist
```shell
kubectl get servicemonitor -A | grep -E "cilium|hubble"
```


- Expected (example):
  - `kube-system cilium-agent` 
  - `kube-system cilium-operator` 
  - `kube-system hubble`

---

### 5) Prometheus discovery issue we hit (and how we fixed it)
- Symptom

- Prometheus query returned no Cilium/Hubble jobs:

```shell
up{namespace="kube-system", job=~".*hubble.*|.*cilium.*"}
```

- Root cause

- The Prometheus CR showed:

```yaml
serviceMonitorNamespaceSelector: {}
serviceMonitorSelector:  
```


- (i.e., `serviceMonitorSelecto`r rendered blank / null)

- What I checked
```yaml
helm -n monitoring get values kps
helm -n monitoring get manifest kps | grep -n "serviceMonitorSelector" | head -n 20

kubectl -n monitoring get prometheus kps-kube-prometheus-stack-prometheus -o yaml | \
  sed -n '/serviceMonitorNamespaceSelector:/,/serviceMonitorSelector:/p'
```

- Fix approach (recommended)

- Use kube-prometheus-stack values that explicitly allow selecting all ServiceMonitors/PodMonitors:

- Create `kps-values.yaml`:

```yaml
prometheus:
  prometheusSpec:
    serviceMonitorNamespaceSelector: {}
    serviceMonitorSelector: {}
    podMonitorNamespaceSelector: {}
    podMonitorSelector: {}
```


- Apply:

```shell
helm upgrade kps prometheus-community/kube-prometheus-stack -n monitoring -f kps-values.yaml
kubectl -n monitoring rollout status deploy/kps-kube-prometheus-stack-operator
```


- If Helm still renders blank selectors, patch the Prometheus CR with JSON patch:

```shell
kubectl -n monitoring patch prometheus kps-kube-prometheus-stack-prometheus \
  --type='json' \
  -p='[
    {"op":"add","path":"/spec/serviceMonitorSelector","value":{}},
    {"op":"add","path":"/spec/podMonitorSelector","value":{}},
    {"op":"add","path":"/spec/serviceMonitorNamespaceSelector","value":{}},
    {"op":"add","path":"/spec/podMonitorNamespaceSelector","value":{}}
  ]'
```
---
### 6) Verify scraping in Prometheus (UI + queries)
### 6.1 Port-forward Prometheus UI
```shell
kubectl -n monitoring port-forward svc/kps-kube-prometheus-stack-prometheus 9090:9090
```


- Open:
  - `http://127.0.0.1:9090`

### 6.2 PromQL verification queries (Prometheus UI)

- All targets up

- up


- Only kube-system targets

```yaml
up{namespace="kube-system"}


Cilium + Hubble targets

up{job=~".*hubble.*|.*cilium.*"}


List all Hubble metrics

{__name__=~"hubble_.*"}


List all Cilium drop metrics

{__name__=~"cilium_.*drop.*"}
```

7) Make Grafana dashboard


- Check if Grafana is already installed by kube-prometheus-stack:

```shell
kubectl -n monitoring get svc | grep -i grafana
```

- If it exists, access it
```yaml
kubectl -n monitoring port-forward svc/kps-grafana 3000:80
```


- Then open: `http://localhost:3000`

- Default login is commonly:
  - `user`: `admin`
  - `password`: from `secret`:

```yaml
kubectl -n monitoring get secret kps-grafana -o jsonpath="{.data.admin-password}" | base64 -d; echo
```
- What dashboards to add

- add:
  - Cilium Agent / Dataplane dashboard (health, drops, policy)
  - Hubble dashboard (flows, drops, DNS, L7 if enabled)
- Optional: make Hubble “less empty” by generating real traffic 
  - Right now flows might be low. Create a quick test:

```yaml
kubectl create ns demo-traffic
kubectl -n demo-traffic run curl --image=curlimages/curl:8.5.0 -it --rm -- sh

# inside:
for i in $(seq 1 50); do curl -s https://kubernetes.default.svc >/dev/null; done
exit
```


### 7.1 Connect Prometheus datasource and confirm datasource works

- Grafana → Data sources → Prometheus
- URL used, though it already in there as default:
  - `http://kps-kube-prometheus-stack-prometheus.monitoring:9090/`

- Grafana should show:
  - “Successfully queried the Prometheus API”

### 8) Build Grafana Dashboard: “Cilium + Hubble Overview”
### 8.1 Where to queries

- Grafana → Explore → select Prometheus datasource → switch to Code → then PromQL.

### 8.2 Dashboard structure (A → G)

Create dashboard: Cilium + Hubble Overview

```yaml
#Panel A — Hubble flows/sec (cluster) | Time series
sum(rate(hubble_flows_processed_total{job="hubble-metrics"}[5m]))

#Panel B — Hubble drops/sec (cluster) | Time series
sum(rate(hubble_drop_total{job="hubble-metrics"}[5m]))

#Panel C — Flows/sec by node | Time series
sum by (node) (
  rate(hubble_flows_processed_total{job="hubble-metrics"}[5m])
)

#Panel D — Drops/sec by node | Time series
sum by (node) (
  rate(hubble_drop_total{job="hubble-metrics"}[5m])
)


#Important Grafana setting: set query Type = Range (not “Both”) to avoid confusing duplicate behavior.

#Panel E — Top namespaces by flows | Table
topk(10, sum by (source_namespace) (
  rate(hubble_flows_processed_total{job="hubble-metrics"}[5m])
))


#Transformations:

#Labels to fields

#(Optional) Organize fields: keep source_namespace, Value; rename Value → flows_per_sec

#Panel F — Top namespaces by drops | Table
topk(10, sum by (source_namespace) (
  rate(hubble_drop_total{job="hubble-metrics"}[5m])
))


#Transformations: same as Panel E

#Panel G — Scrape health | Stat
min(up{job=~"hubble-metrics|cilium-agent|cilium-operator"})
```


- Stat options:
  - Reduce: Last 
  - Thresholds: 0 red, 1 green

---

### 9) Dashboard Variable (for investigation)

- Dashboard → Settings → Variables → New 
  - Name: node 
  - Type: Query 
  - Query:

```yaml
label_values(up{job="hubble-metrics"}, node)
```


- Example node-filtered panel query:

```yaml
sum(rate(hubble_flows_processed_total{job="hubble-metrics", node=~"$node"}[5m]))
```

### 10) Add “Cilium Enterprise” Row (Cilium drop insights)
### 10.1 Discover drop metric

- verified Cilium drops are exposed with:

```yaml
{__name__=~"cilium_.*drop.*"}
```


- use the metric:
  - cilium_drop_count_total
  Labels confirmed:
  - node, reason, direction

---

### 10.2 Panels to add
```yaml
#Panel 1 — Cilium components UP | Stat
min(up{job=~"cilium-agent|cilium-operator"})

#Panel 2 — Cilium drops/sec (cluster) | Time series
sum(rate(cilium_drop_count_total[5m]))

#Panel 3 — Drops/sec by node | Time series
sum by (node) (rate(cilium_drop_count_total[5m]))

#Panel 4 — Top drop reasons | Table
topk(10, sum by (reason) (rate(cilium_drop_count_total[5m])))
```


- Transformations:
  - Labels to fields
  - (Optional) Organize fields: keep `reason`, `Value`; rename `Value` → `drops_per_sec`

```yaml
#Panel 5 — Top node+reason drops | Table
topk(10, sum by (node, reason) (rate(cilium_drop_count_total[5m])))
```


- Transformations:
  - Labels to fields
  - (Optional) Organize fields: keep `node`, `reason`, `Value`; rename `Value` → `drops_per_sec`

```yaml
#Optional panels — Ingress vs Egress drops | Time series
sum(rate(cilium_drop_count_total{direction="EGRESS"}[5m]))

sum(rate(cilium_drop_count_total{direction="INGRESS"}[5m]))
```
---

### 11) Hubble UI access (optional, for live traffic exploration)
### 11.1 Port-forward on jumpbox
```shell
kubectl -n kube-system port-forward svc/hubble-ui 12000:80
```

### 11.2 SSH tunnel from your workstation (Windows example)
- `ssh -L 5000:127.0.0.1:12000 user@ip`


- Open:
  - `http://127.0.0.1:5000`

### 12) Troubleshooting checklist
### A) “No data sources found” in Grafana

- Fix:
  - Ensure Prometheus datasource exists and “Save & test” passes. 
  - URL example: `http://kps-kube-prometheus-stack-prometheus.monitoring:9090/`

### B) Prometheus doesn’t show hubble/cilium jobs

- Check:

```shell
up{job=~".*hubble.*|.*cilium.*"}
```


- If empty:

- Verify ServiceMonitors exist:

```shell
kubectl get servicemonitor -A | grep -E "cilium|hubble"
```


- Verify Prometheus CR selectors:

```shell
kubectl -n monitoring get prometheus kps-kube-prometheus-stack-prometheus -o yaml | \
  sed -n '/serviceMonitorNamespaceSelector:/,/serviceMonitorSelector:/p'
```


- Apply the kps-values.yaml fix (Section 5)

### C) Grafana per-node panel shows “duplicates”

- Fix:
  - Ensure panel query Type = Range 
  - Ensure you’re not using debug count by (...) queries 
  - Use job="hubble-metrics" filter and group sum by (node)

[Appendix: All PromQL queries used]()
- Discovery / debug
```yaml
up
up{namespace="kube-system"}
up{job=~".*hubble.*|.*cilium.*"}
{__name__=~"hubble_.*"}
{__name__=~"cilium_.*drop.*"}
count by (node) (up{job="hubble-metrics"})
count by (node, instance, endpoint, container, pod, service, namespace) (rate(hubble_flows_processed_total{job="hubble-metrics"}[5m]))

```
- Hubble dashboard (A–G)
```yaml
sum(rate(hubble_flows_processed_total{job="hubble-metrics"}[5m]))
sum(rate(hubble_drop_total{job="hubble-metrics"}[5m]))
sum by (node) (rate(hubble_flows_processed_total{job="hubble-metrics"}[5m]))
sum by (node) (rate(hubble_drop_total{job="hubble-metrics"}[5m]))
topk(10, sum by (source_namespace) (rate(hubble_flows_processed_total{job="hubble-metrics"}[5m])))
topk(10, sum by (source_namespace) (rate(hubble_drop_total{job="hubble-metrics"}[5m])))
min(up{job=~"hubble-metrics|cilium-agent|cilium-operator"})
label_values(up{job="hubble-metrics"}, node)
sum(rate(hubble_flows_processed_total{job="hubble-metrics", node=~"$node"}[5m]))
```

- Cilium “enterprise” drops
```yaml
min(up{job=~"cilium-agent|cilium-operator"})
sum(rate(cilium_drop_count_total[5m]))
sum by (node) (rate(cilium_drop_count_total[5m]))
topk(10, sum by (reason) (rate(cilium_drop_count_total[5m])))
topk(10, sum by (node, reason) (rate(cilium_drop_count_total[5m])))
sum(rate(cilium_drop_count_total{direction="EGRESS"}[5m]))
sum(rate(cilium_drop_count_total{direction="INGRESS"}[5m]))
```

## [Reference - Prometheus official Documentation](https://prometheus.io/docs/introduction/overview/)
## [Reference - Grafana official Documentation](https://grafana.com/docs/) 