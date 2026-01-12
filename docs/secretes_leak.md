### TL;DR (Do this in order)
1) Make repo private (stop exposure)
2) Rotate Talos CA: `talosctl rotate-ca --talos=true --kubernetes=false`
3) Rotate K8s CA: `talosctl rotate-ca --talos=false --kubernetes=true`
4) Regenerate kubeconfig: `talosctl kubeconfig ./kubeconfig --force --merge=false`
5) Copy kubeconfig to default: `cp ./kubeconfig ~/.kube/config`
6) Install git-filter-repo and purge history of leaked files
7) Force push rewritten history
8) Add .gitignore for talosconfig/kubeconfig/secrets.yaml/controlplane*.yaml/worker*.yaml
9) Add secret scanning (gitleaks) in CI/pre-commit
10) Check forks/PRs; tell collaborators to re-clone

### Known errors and fixes
- `tls: failed to verify certificate (unknown authority)`
  - Cause: using old talosconfig after Talos CA rotation
  - Fix: use the updated talosconfig that matches the new CA

- `rotate-ca hangs / tries to patch VIP (e.g., 192.168.0.210)`
  - Cause: VIP is not a Talos node; rotation should operate on node IPs
  - Fix: ensure endpoints are only real nodes (241/242/243), never VIP

- `kubectl points to http://localhost:8080`
  - Cause: old kubeconfig / wrong context
  - Fix: regenerate kubeconfig, or set cluster server to `https://<VIP>:6443`

- `kubeconfig empty / no contexts`
  - Cause: merge/redirect created an empty file after command failure
  - Fix: generate kubeconfig directly to a file: `talosctl kubeconfig ./kubeconfig --force --merge=false`

- `talosconfig has “no context is set”`
  - Cause: file doesn’t contain contexts or current context not selected
  - Fix: use a valid talosconfig (e.g., talos-prod/talosconfig) and `config use-context <name>`


### Incident Runbook: Talos/Kubernetes Secrets Leaked via Public Git Repo (and How We Fixed It)

> **Audience:** DevOps / Homelab / Platform engineers running Talos + Kubernetes  
> **Goal:** Knowledge transfer + repeatable procedure for handling a Talos/K8s secret leak in Git (public repo)

---

#### 1. Summary

A Talos/Kubernetes cluster was bootstrapped using configs generated via:

- `talosctl gen config`

Some generated files (Talos secrets, talosconfig, kubeconfig, controlplane/worker YAMLs) were accidentally committed to a **public GitHub repository**, exposing cluster credentials and PKI material.

**Outcome:** We rotated Talos and Kubernetes CAs to invalidate leaked credentials, restored working access (`talosctl` + `kubectl`), and rewrote Git history to permanently remove leaked files. We then added guardrails to prevent recurrence.

---

#### 2. Why This Is Critical

When Talos-generated files leak publicly, they can contain:

- Kubernetes bootstrap tokens
- Talos bootstrap / cluster secrets
- Kubeconfig client credentials (client key/cert)
- Talos client credentials (`talosconfig`)
- Encryption secrets and CA/private keys (depending on what was committed)

**Impact:** Anyone who obtains those files can potentially gain cluster access.

---

#### 3. What Was Leaked (Observed Indicators)

We detected secrets in the repo using:

```bash
git grep -nE "BEGIN |aescbc|client-key-data|certificate-authority-data|token:|bootstraptoken" || true
```
- Findings included:
  - token: values in manifest/controlplane-cp*.yaml 
  - bootstraptoken: in manifest/talos-prod/secrets.yaml 
  - client-key-data / certificate-authority-data in kubeconfig files 
  - A talosconfig file inside the repository

- Important: Never paste these secrets into chat, tickets, or screenshots. Treat them as compromised.

---
#### 4. Containment (Immediate Actions)

- Make the repository private immediately.

- Confirm you are not exposing these ports publicly:
  - Kubernetes API: 6443 
  - Talos API: 50000

- (If exposed, treat as urgent and lock down firewall/router immediately.)

---

#### 5. Recommended Fix (Easiest + Correct): Rotate PKI + Replace Access Files

- Because the repo was public and the cluster was already bootstrapped, we chose the safest approach:
  - Rotate Talos API CA 
  - Rotate Kubernetes API CA 
  - Generate fresh kubeconfig 
  - Validate cluster health 
  - Remove secrets from Git history and prevent re-commit

- Cluster Info (this incident)
  - Control planes: `192.168.0.241`, `192.168.0.242`, `192.168.0.243`
  - Worker: `192.168.0.244`
  - Kubernetes VIP (API endpoint): `192.168.0.210`

- Key rule:
  - Talos operations target node IPs (241/242/243), not the VIP. 
  - Kubernetes (`kubectl`) targets the VIP (`210:6443`).

---

#### 6. Fix Part A — Rotate Talos API CA (Invalidate leaked talosconfig)
#### 6.1 Ensure Talos endpoints are correct (no VIP)
```shell
talosctl --talosconfig talos-prod/talosconfig config use-context homelab
talosctl --talosconfig talos-prod/talosconfig config endpoint 192.168.0.241 192.168.0.242 192.168.0.243
talosctl --talosconfig talos-prod/talosconfig config node 192.168.0.241
```
#### 6.2 Verify Talos connectivity
```shell
talosctl --talosconfig talos-prod/talosconfig -n 192.168.0.241 version
```
#### 6.3 Rotate Talos API CA
```shell
talosctl --talosconfig talos-prod/talosconfig -n 192.168.0.241 rotate-ca \
  --dry-run=false --talos=true --kubernetes=false
```


- Expected: Rotation completes successfully and updates Talos access.

> Note: Rotation output can include base64 blobs. Avoid sharing that output.

---

#### 7. Fix Part B — Rotate Kubernetes API CA (Invalidate leaked kubeconfig/tokens)
#### 7.1 Run Kubernetes CA rotation (do not Ctrl+C)

- This can take time; run inside `tmux` to avoid interruption:

```shell
tmux new -s k8s-ca
```


- Then:

```shell
talosctl --talosconfig talos-prod/talosconfig \
  -n 192.168.0.241 rotate-ca \
  --dry-run=false --talos=false --kubernetes=true
```


- Important: If you interrupt it, re-run it fully. It’s safe to re-run.

---

#### 8. Fix Part C — Restore Working kubectl Access
### 8.1 Fetch kubeconfig (no merge, overwrite file)
```shell
rm -f ./kubeconfig
talosctl --talosconfig talos-prod/talosconfig -n 192.168.0.241 \
  kubeconfig ./kubeconfig --force --merge=false
```

#### 8.2 Test using explicit kubeconfig
```shell
KUBECONFIG=./kubeconfig kubectl get pods -A
KUBECONFIG=./kubeconfig kubectl get nodes -o wide
```


#### 8.3 Make it the default (recommended long-term)
```shell
mkdir -p ~/.kube
cp -v ~/.kube/config ~/.kube/config.backup.$(date +%F-%H%M%S) 2>/dev/null || true

cp -v ./kubeconfig ~/.kube/config
chmod 600 ~/.kube/config
```


- Confirm:
```shell
kubectl get nodes -o wide
kubectl get pods -A
```
---

#### 9. Fix Part D — Purge Secrets from Git History (Public Repo Cleanup)
#### 9.1 Install `git-filter-repo`

- Ubuntu/Debian:

```shell
sudo apt update
sudo apt install -y git-filter-repo
```


- If unavailable:

```shell
sudo apt install -y pipx
pipx install git-filter-repo
pipx ensurepath
```


- Verify:

```shell
git filter-repo --help | head
```

#### 9.2 Clone into a clean working directory
```shell
cd ~
git clone <your-repo-url> homelab-clean
cd homelab-clean
```

#### 9.3 Rewrite history to remove sensitive files

- (Adjust file paths to your repo.)

```shell
git filter-repo \
  --path manifest/controlplane-cp1.yaml \
  --path manifest/controlplane-cp2.yaml \
  --path manifest/controlplane-cp3.yaml \
  --path manifest/talos-prod/secrets.yaml \
  --path manifest/talos-prod/controlplane.yaml \
  --path manifest/talos-prod/worker.yaml \
  --path manifest/talos-prod/worker-w1.yaml \
  --path manifest/talos-prod/alternative-kubeconfig \
  --path manifest/talosconfig \
  --invert-paths
```

#### 9.4 Force push rewritten history
```shell
git remote add origin git@github.com:<user>/<repo>.git  # if needed
git push --force --all
git push --force --tags
```

#### 9.5 Verify secrets are gone
```shell
git grep -nE "BEGIN |aescbc|client-key-data|certificate-authority-data|token:|bootstraptoken" || echo "OK: no secrets found"
```

---


#### 10. Prevention (Hard Guardrails)
#### 10.1 Add .gitignore (must-have)
```shell
# Talos / K8s secrets (NEVER commit)
**/secrets.yaml
**/talosconfig
**/*kubeconfig*
**/controlplane*.yaml
**/worker*.yaml
manifest/talos-prod/*.yaml
manifest/controlplane-cp*.yaml

# Keys/certs
*.key
*.pem
*.p12
```

#### 10.2 Keep only safe artifacts in the public repo

✅ Safe:

- static network configs (no tokens/keys)

- patches (no secrets)

- app manifests (no credentials)

❌ Never public:

- secrets.yaml

- talosconfig

- any kubeconfig

- generated controlplane.yaml/worker.yaml containing tokens/keys

#### 10.3 Add secret scanning (recommended)

- Add `gitleaks` / `trufflehog` as a pre-commit hook and in CI 
- Fail PRs/commits that include `client-key-data`, `certificate-authority-data`, `token:`, etc.

#### 11. Post-Incident Checklist

- Repo set to private during cleanup 
- Talos API CA rotated 
- Kubernetes API CA rotated 
- Fresh kubeconfig fetched and working
- `~/.kube/config` updated (or merged) and working 
- History rewritten with `git filter-repo`
- Verified repo contains no secrets (`git grep ...`)
- `.gitignore` added 
- Secret scanning enabled (pre-commit + CI)
- Forks/PRs reviewed (public repo risk)
- Team notified to re-clone due to force-push history rewrite

#### 12. Lessons Learned

- Never commit generated Talos/Kube configs to a public repo. 
- Rotation fixes the risk; history purge only cleans the repo. 
- VIP is for Kubernetes, not Talos endpoints. 
- Use `tmux` for long-running PKI operations (avoid Ctrl+C mid-rotation). 
- Add scanners + gitignore early.