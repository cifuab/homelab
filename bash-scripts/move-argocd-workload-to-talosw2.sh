#!/bin/bash

kubectl -n argocd patch statefulset my-argo-cd-argocd-application-controller \
  --type='merge' \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/hostname":"talos-w2"}}}}}'

kubectl -n argocd patch deployment my-argo-cd-argocd-applicationset-controller \
  --type='merge' \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/hostname":"talos-w2"}}}}}'

kubectl -n argocd patch deployment my-argo-cd-argocd-dex-server \
  --type='merge' \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/hostname":"talos-w2"}}}}}'

kubectl -n argocd patch deployment my-argo-cd-argocd-notifications-controller \
  --type='merge' \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/hostname":"talos-w2"}}}}}'

kubectl -n argocd patch deployment my-argo-cd-argocd-redis \
  --type='merge' \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/hostname":"talos-w2"}}}}}'

kubectl -n argocd patch deployment my-argo-cd-argocd-repo-server \
  --type='merge' \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/hostname":"talos-w2"}}}}}'

kubectl -n argocd patch deployment my-argo-cd-argocd-server \
  --type='merge' \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/hostname":"talos-w2"}}}}}'
