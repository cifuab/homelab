### Alloy Config Setup
```yaml
controller:
  type: daemonset
  nodeSelector:
    node-role.kubernetes.io/control-plane: ""
  tolerations:
    - operator: Exists
  volumes:
    extra:
      - name: auditlog
        hostPath:
          path: /var/log/audit/kube
          type: DirectoryOrCreate

alloy:
  configMap:
    create: true
    content: |
      local.file_match "k8s_audit" {
        path_targets = [{
          __address__ = "localhost",
          __path__    = "/var/log/audit/kube/kube-apiserver*.log",
        }]
      }

      loki.source.file "audit" {
        targets       = local.file_match.k8s_audit.targets
        forward_to    = [loki.process.audit.receiver]
        tail_from_end = true
      }

      loki.process "audit" {
        forward_to = [loki.write.local.receiver]

        stage.static_labels {
          values = {
            job    = "k8s-audit",
            stream = "k8s-audit",
            source = "apiserver-audit",
            node   = constants.hostname,
          }
        }

        stage.json {
          expressions = {
            stage     = "stage",
            verb      = "verb",
            user      = "user.username",
            namespace = "objectRef.namespace",
            resource  = "objectRef.resource",
            code      = "responseStatus.code",
            uri       = "requestURI",
          }
        }

        // Keep only final audit outcome by dropping intermediate stages.
        stage.drop {
          source = "stage"
          value  = "RequestReceived"
        }

        stage.drop {
          source = "stage"
          value  = "ResponseStarted"
        }

        // Drop successful leader-election noise.
        stage.drop {
          source     = "resource,code"
          separator  = ";"
          expression = "^leases;2.*$"
        }

        // Drop successful WATCH noise.
        stage.drop {
          source     = "verb,code"
          separator  = ";"
          expression = "^watch;2.*$"
        }

        // Drop successful get/list/read noise.
        stage.drop {
          source     = "verb,code"
          separator  = ";"
          expression = "^(get|list);2.*$"
        }

        stage.labels {
          values = {
            verb = "verb",
            code = "code",
          }
        }
      }

      loki.write "local" {
        endpoint {
          url = "http://loki.logging.svc.cluster.local:3100/loki/api/v1/push"
          headers = {
            "X-Scope-OrgID" = "1",
          }
        }
      }

  mounts:
    extra:
      - name: auditlog
        mountPath: /var/log/audit/kube
        readOnly: true
```
- Apply changes
```shell
# 1) back up the current live values/config first
helm -n logging get values alloy-audit > alloy-audit-values.backup.yaml
kubectl -n logging get configmap alloy-audit -o yaml > alloy-audit-configmap.backup.yaml

# 2) edit your values file
nano alloy-audit-values.yaml

# 3) apply with Helm
helm upgrade --install alloy-audit grafana/alloy \
  -n logging \
  -f alloy-audit-values.yaml

# 4) force a clean restart so all pods load the same config
kubectl -n logging rollout restart daemonset alloy-audit

# 5) watch rollout
kubectl -n logging rollout status daemonset alloy-audit
kubectl -n logging get pods -o wide
```
- verify

```shell
# pod health
kubectl -n logging get pods -o wide

# alloy logs
kubectl -n logging logs -l app.kubernetes.io/instance=alloy-audit -c alloy --tail=80

# confirm rendered config in-cluster
kubectl -n logging get configmap alloy-audit -o jsonpath='{.data.config\.alloy}'
```

- Debug and Rollout/Rollback
```shell
helm -n logging history alloy-audit
helm -n logging get values alloy-audit --revision 10
kubectl -n logging describe pod alloy-audit-cd2dr
kubectl -n logging logs alloy-audit-cd2dr -c alloy --tail=100
kubectl -n logging logs alloy-audit-cd2dr -c config-reloader --tail=50
talosctl -n 192.168.0.242 ls /var/log/audit/kube
talosctl -n 192.168.0.242 read /var/log/audit/kube/kube-apiserver*.log
kubectl -n logging delete pod alloy-audit-cd2dr
kubectl -n logging get pods -o wide -w
kubectl -n logging get ds alloy-audit -o yaml | grep -A3 -B3 'checksum\|config'
kubectl -n logging describe ds alloy-audit
```

