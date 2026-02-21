## Prometheus

### A) Provisioning and sharing
```shell
GRAFANA_URL="http://localhost:8000"
DASH_UID="adg9q66"

curl -sS -u "admin:admin" \
  "$GRAFANA_URL/api/dashboards/uid/$DASH_UID" \
| jq '.dashboard | del(.id,.version)' \
> /mnt/data/homelab/grafana/panels/talos-cilium-dashboard.provision.json
```

### B) Others and future fresh Grafana (import as new copy)
```shell
GRAFANA_URL="http://localhost:8000"
DASH_UID="adg9q66"

curl -sS -u "admin:admin" \
  "$GRAFANA_URL/api/dashboards/uid/$DASH_UID" \
| jq '.dashboard | del(.id,.uid,.version)' \
> /mnt/data/homelab/grafana/panels/talos-cilium-dashboard.import-newcopy.json
```
### C) Backup/debug version (metadata included)

```shell
GRAFANA_URL="http://localhost:8000"
DASH_UID="adg9q66"

curl -sS -u "admin:admin" \
  "$GRAFANA_URL/api/dashboards/uid/$DASH_UID" \
| jq '.' > /mnt/data/homelab/grafana/panels/talos-cilium-dashboard-full.json
```
---

## Loki

### A) Provisioning and sharing
```shell
GRAFANA_URL="http://localhost:8000"
DASH_UID="k8s-audit-enterprise"

curl -sS -u "admin:admin" \
  "$GRAFANA_URL/api/dashboards/uid/$DASH_UID" \
| jq '.dashboard | del(.id,.version)' \
> /mnt/data/homelab/grafana/panels/audit-soc-dashboard.provision.json
```

### B) Others and future fresh Grafana (import as new copy)
```shell
GRAFANA_URL="http://localhost:8000"
DASH_UID="k8s-audit-enterprise"

curl -sS -u "admin:admin" \
  "$GRAFANA_URL/api/dashboards/uid/$DASH_UID" \
| jq '.dashboard | del(.id,.uid,.version)' \
> /mnt/data/homelab/grafana/panels/audit-soc-dashboard.import-newcopy.json
```

### C) Backup/debug version (metadata included)
```shell
GRAFANA_URL="http://localhost:8000"
DASH_UID="k8s-audit-enterprise"

curl -sS -u "admin:admin" \
  "$GRAFANA_URL/api/dashboards/uid/$DASH_UID" \
| jq '.' \
> /mnt/data/homelab/grafana/panels/audit-soc-dashboard.full.payload.json
```
