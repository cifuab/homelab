#!/bin/bash

cat > /mnt/data/homelab/k8s/manifest/promtail-audit-values.yaml <<'YAML'
config:
  clients:
    - url: http://loki-gateway.logging.svc.cluster.local/loki/api/v1/push

  snippets:
    scrapeConfigs: |
      - job_name: k8s-audit-apiserver
        static_configs:
          - targets:
              - localhost
            labels:
              job: k8s-audit
              component: kube-apiserver
              # Wildcard ensures we catch rotated logs (.log.1, etc)
              __path__: /var/log/audit/kube/*.log
        
        pipeline_stages:
          - json:
              expressions:
                verb: verb
                user: user.username
                groups: user.groups
                namespace: objectRef.namespace
                resource: objectRef.resource
                name: objectRef.name
                subresource: objectRef.subresource
                code: responseStatus.code
                uri: requestURI
          
          # 1. Filter out the noise before labeling
          # Drops "get", "list", "watch" and high-traffic "leases" (leader election)
          - match:
              selector: '{verb=~"get|list|watch"} | {resource="leases"}'
              action: drop

          # 2. Extract labels for the remaining high-value events
          - labels:
              verb:
              user:
              namespace:
              resource:
              subresource:
              code:

# Required for Promtail to read host logs on Talos safely
podSecurityContext:
  runAsUser: 0
  runAsGroup: 0

# Ensure it runs on all 3 control plane nodes
tolerations:
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
  - operator: Exists

nodeSelector:
  node-role.kubernetes.io/control-plane: ""

extraVolumes:
  - name: auditlog
    hostPath:
      path: /var/log/audit/kube
      type: Directory

extraVolumeMounts:
  - name: auditlog
    mountPath: /var/log/audit/kube
    readOnly: true

# Passes the node name to Promtail to distinguish the 3 nodes in Loki
extraArgs:
  - -client.external-labels=hostname=$(NODE_NAME)

env:
  - name: NODE_NAME
    valueFrom:
      fieldRef:
        fieldPath: spec.nodeName
YAML
