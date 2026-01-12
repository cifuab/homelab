
## kubectl can’t talk to the cluster — Troubleshooting Playbook (drop-in)

This guide helps when commands like `kubectl get nodes` fail with:
- TLS handshake timeout
- connection refused / reset by peer
- i/o timeout
- x509 / certificate errors
- “no such host”
- “context was not found”
- “You must be logged in to the server”
- random localhost port like `https://127.0.0.1:45559`

---

### 0) Quick triage checklist (2 minutes)

Run:

```bash
kubectl version --client
kubectl config current-context
kubectl config get-contexts
kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}{"\n"}'
```
Interpretation:

- If server is `https://127.0.0.1:<random>` → you’re using a local proxy/tunnel/provider (kind, Docker Desktop, Rancher Desktop, WSL forwarding). The backend is often stopped.

- If server is `https://<ip>:6443` → remote control plane endpoint. Check network/DNS/firewall and API server health.

- If current-context is empty → kubeconfig not set or broken.

1) Verify you’re using the kubeconfig you think you are

1.1 Check KUBECONFIG and default file

- Linux/macOS
```shell
echo "$KUBECONFIG"
ls -la ~/.kube/config
```
- Powershell
```shell
echo $env:KUBECONFIG
Get-Item $env:USERPROFILE\.kube\config
```
- If `KUBECONFIG` is set, kubectl may not use `~/.kube/config`.

1.2 Print the exact server kubectl targets
```shell
kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}{"\n"}'
```

2) Basic connectivity: is the endpoint reachable?

2.1 If the server is an IP/DNS (typical kubeadm/Talos)

- Linux/macOS
```shell
ENDPOINT=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
echo "$ENDPOINT"
# If endpoint is https://X:6443, test reachability:
curl -k --connect-timeout 5 "${ENDPOINT}/healthz" || true
nc -vz <CONTROL_PLANE_IP_OR_DNS> 6443
```
- PowerShell
```shell
$ep = kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'
$ep
# If endpoint is https://X:6443, test port:
Test-NetConnection <CONTROL_PLANE_IP_OR_DNS> -Port 6443
```
If port 6443 is not reachable:

- VPN/Tailscale/offline network

- firewall/security group

- wrong IP/VIP/DNS

- control plane is down

2.2 If the server is localhost with random port (kind / Desktop K8s / WSL)

- Check if anything is listening:

- Linux/macOS

```shell
# replace PORT
lsof -iTCP:<PORT> -sTCP:LISTEN || true
```


- PowerShell

```shell
Test-NetConnection 127.0.0.1 -Port <PORT>
Get-NetTCPConnection -LocalPort <PORT> -ErrorAction SilentlyContinue
```


- If nothing listens, start the underlying provider (Docker Desktop, Rancher Desktop, kind, etc.)

3) Common failure modes and fixes

A) TLS handshake timeout / i/o timeout

- Symptoms

  - TLS handshake timeout

  - context deadline exceeded

  - i/o timeout

- Likely causes

  - cluster API endpoint not reachable (network/VPN)

  - API server overloaded/down

  - localhost proxy/tunnel died

- Fix

1. Identify server endpoint:

```shell
kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}{"\n"}'
```
2. Test port reachability (see section 2).

3. If endpoint is `127.0.0.1:<random>`:

   - start your provider (Docker Desktop / Rancher Desktop)

   - if kind:
```shell
kind get clusters
kind export kubeconfig --name <cluster-name>
```


4. If endpoint is remote :6443, verify VPN/Tailscale and control plane health.

B) `connection refused` / `connection reset by peer`

- Symptoms

  - connect: connection refused

  - read: connection reset by peer

- Likely causes

  - endpoint reachable but API server not listening or restarting

  - kube-apiserver crashed

  - proxy port exists but backend process died

- Fix

  - Remote cluster:

    - Check 6443 reachability. 
    - On control plane:
      - kubeadm: check static pod / container runtime logs for kube-apiserver 
      - Talos: check API status via talosctl (if applicable)

  - Localhost endpoint:

    - restart provider / recreate tunnel

C) `x509: certificate signed by unknown authority`

 - Symptoms

    - x509 unknown authority

    - certificate verification failure

 - Likely causes

   - wrong kubeconfig / wrong CA cert

   - cluster rotated certs, your kubeconfig is old

   - MITM proxy/corporate inspection (rare)

 - Fix

   - Ensure you’re using correct kubeconfig. 
   - Re-fetch kubeconfig from control plane/provider. 
   - For kubeadm:
     - copy /etc/kubernetes/admin.conf from control plane (securely) into ~/.kube/config

   - For managed clusters (EKS/AKS/GKE):

     - regenerate kubeconfig using provider tooling.

D) The connection to the server <x> was refused + current-context must exist

- Symptoms

  - current-context must exist 
  - commands fail immediately 
  - empty current context

- Fix 
  - List contexts:

```shell
kubectl config get-contexts
```


- Set one:

```shell
kubectl config use-context <context-name>
```


- If no contexts exist, your kubeconfig is missing/broken → restore it.

E) `You must be logged in to the server (Unauthorized) / forbidden`

- Symptoms 
  - Unauthorized / forbidden 
  - RBAC denies

- Likely causes 
  - expired token (OIDC)
  - wrong user / wrong cluster 
  - missing credentials in kubeconfig 
  - RBAC not granted for your identity

- Fix

  - Confirm identity:

```shell
kubectl config view --minify
```


- If OIDC:

  - re-login / refresh token (depends on setup)

- Managed cluster:

  - re-run aws eks update-kubeconfig / az aks get-credentials / gcloud container clusters get-credentials

- RBAC:
  - ask cluster admin to grant required roles.

F) no such host / DNS errors

- Symptoms

  - no such host

  - DNS lookup failures

- Fix

  - Ensure DNS resolves:

```shell
nslookup <endpoint-hostname>
```


- Check VPN split-DNS / corporate DNS / /etc/resolv.conf.

- If using internal VIP DNS, verify you’re on the right network.

G) Works in WSL but not in Windows (or vice versa)

- Symptoms

  - same kubeconfig, one environment fails

  - localhost endpoints break across environments

- Fix

  - If server is `127.0.0.1:<port>`, run kubectl in the same environment where the provider runs:

    - provider in Windows → use Windows kubectl

    - provider in WSL → use WSL kubectl

- Keep separate kubeconfigs per environment if needed.

4) Reset/refresh commands (safe)

4.1 Clean stale contexts (does not delete clusters)
````shell
kubectl config get-contexts
# optionally:
kubectl config delete-context <name>
kubectl config delete-cluster <name>
kubectl config delete-user <name>
````

4.2 Verify cluster reachability without kubectl caching noise
```shell
kubectl --request-timeout=5s get --raw='/healthz' || true
kubectl --request-timeout=5s get --raw='/readyz' || true
```

5) Provider-specific quick fixes
- kind (local)
```shell
kind get clusters
kind export kubeconfig --name <cluster-name>
kubectl get nodes
```

- Docker Desktop / Rancher Desktop

  - Ensure Kubernetes is enabled + running in the UI.

  - Switch context:

```shell
kubectl config get-contexts
kubectl config use-context <desktop-context>
kubectl get nodes
```

- kubeadm (remote)
  - Endpoint should typically be `https://<VIP-or-CP>:6443` 
  - If endpoint changed, update kubeconfig server value. 
  - If certs rotated, recopy kubeconfig.

6) When you’re fully stuck: capture a debug bundle

- Run and save output:

```shell
kubectl config current-context
kubectl config view --minify
kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}{"\n"}'
kubectl get nodes -v=8
```


- This shows whether the failure is:
  - kubeconfig/context 
  - network/endpoint 
  - auth/certs 
  - API server health