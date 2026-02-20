#!/bin/bash

cat > /mnt/data/homelab/k8s/manifest/alloy-audit-values.yaml <<'YAML'
alloy:
  configReloader:
    enabled: true
  config: |
    local.file_match "k8s_audit" {
      path_targets = [{
        __address__ = "localhost",
        __path__    = "/var/log/audit/kube/*.log",
        job         = "k8s-audit",
        hostname    = constants.hostname,
      }]
    }

    loki.process "audit_logs" {
      forward_to = [loki.write.local.receiver]

      stage.json {
        expressions = {
          verb      = "verb",
          user      = "user.username",
          namespace = "objectRef.namespace",
          resource  = "objectRef.resource",
          code      = "responseStatus.code",
          uri       = "requestURI",
        }
      }

      # Drop high-volume noise
      stage.match {
        selector = "{verb=~\"get|list|watch\"}"
        action   = "drop"
      }
      stage.match {
        selector = "{resource=\"leases\"}"
        action   = "drop"
      }

      stage.labels {
        values = {
          verb      = null,
          user      = null,
          namespace = null,
          resource  = null,
          code      = null,
        }
      }
    }

    loki.source.file "audit" {
      targets    = local.file_match.k8s_audit.targets
      forward_to = [loki.process.audit_logs.receiver]
    }

    loki.write "local" {
      endpoint {
        url = "http://loki-gateway.logging.svc.cluster.local/loki/api/v1/push"
      }
    }

  mounts:
    extra:
      - name: auditlog
        mountPath: /var/log/audit/kube
        readOnly: true

controller:
  type: daemonset
  nodeSelector:
    node-role.kubernetes.io/control-plane: ""
  tolerations:
    - key: node-role.kubernetes.io/control-plane
      operator: Exists
      effect: NoSchedule
    - key: node-role.kubernetes.io/master
      operator: Exists
      effect: NoSchedule
    - operator: Exists

  volumes:
    extra:
      - name: auditlog
        hostPath:
          path: /var/log/audit/kube
          type: Directory

podSecurityContext:
  runAsUser: 0
  runAsGroup: 0

containerSecurityContext:
  privileged: true

env:
  - name: NODE_NAME
    valueFrom:
      fieldRef:
        fieldPath: spec.nodeName
YAML



