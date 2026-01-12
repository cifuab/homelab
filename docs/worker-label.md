- This label worker node if it show ROLES <none>
```shell
kubectl label node talos-cfi-xtb node-role.kubernetes.io/worker=""
```
- To confirm it’s a worker the “real” way:
```shell
kubectl get node talos-cfi-xtb -o jsonpath='{.metadata.labels}' | tr ' ' '\n' | grep role
kubectl describe node talos-cfi-xtb | egrep -i 'Roles|Labels|Taints'
```

