#!/bin/bash

helm install my-argo-cd argo/argo-cd \
  --version 9.4.17 \
  -n argocd \
  --wait \
  --timeout 15m \
  --set global.nodeSelector."kubernetes\.io/hostname"=talos-w1 \
  --set redis.image.repository=docker.io/redis \
  --set redis.image.tag=8.2.3-alpine
