# Kubernetes Security Hardening — k3s Lab Guide

Practical security hardening for the k3s cluster in the DevOps lab. It covers CIS Kubernetes Benchmark controls, Falco runtime rules, Kyverno admission policies, RBAC configuration, and network policies. All examples reference the actual cluster in `labs/infrastructure/devops-linux-lab/`.

**Cluster control plane:** `devops-1` (auto-detected IP, octet .114)  
**Kubeconfig:** `/vagrant/kubeconfig.yaml` or `/etc/rancher/k3s/k3s.yaml`

***

## Table of Contents

1. [Setup and Access](#1-setup-and-access)
2. [CIS Benchmark Assessment](#2-cis-benchmark-assessment)
3. [RBAC — Role-Based Access Control](#3-rbac--role-based-access-control)
4. [Network Policies](#4-network-policies)
5. [Pod Security Standards](#5-pod-security-standards)
6. [Falco Runtime Security](#6-falco-runtime-security)
7. [Kyverno Policy Enforcement](#7-kyverno-policy-enforcement)
8. [Secrets Management](#8-secrets-management)
9. [Image Security with Harbor and Trivy](#9-image-security-with-harbor-and-trivy)
10. [Audit Logging](#10-audit-logging)
11. [Cert-Manager TLS Hardening](#11-cert-manager-tls-hardening)
12. [Node Hardening](#12-node-hardening)
13. [Hardening Verification Checklist](#13-hardening-verification-checklist)

***

## 1. Setup and Access

### Connect to the Cluster

```bash
# From your host machine via SSH to devops-1
vagrant ssh devops-1

# Set KUBECONFIG
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Verify access
kubectl get nodes
kubectl cluster-info
kubectl version --short
```

### Install Security Tools

```bash
# kube-bench — CIS benchmark scanner
curl -L https://github.com/aquasecurity/kube-bench/releases/latest/download/kube-bench_linux_amd64.tar.gz \
  | tar -xz -C /usr/local/bin kube-bench

# kubescape — security posture scanner
# Download, inspect, then run — piping curl directly to a shell executes
# whatever that URL returns with your current privileges, with no chance
# to review it first. Downloading a script doesn't make it trustworthy;
# read it before running it.
curl -s https://raw.githubusercontent.com/kubescape/kubescape/master/install.sh -o /tmp/kubescape-install.sh
less /tmp/kubescape-install.sh   # inspect before running
chmod +x /tmp/kubescape-install.sh
bash /tmp/kubescape-install.sh
rm -f /tmp/kubescape-install.sh

# kubectl-neat — clean up verbose kubectl output
kubectl krew install neat

# kube-score — static analysis of manifests
curl -L https://github.com/zegl/kube-score/releases/latest/download/kube-score_linux_amd64.tar.gz \
  | tar -xz -C /usr/local/bin

# trivy — image and config vulnerability scanner
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
  | sh -s -- -b /usr/local/bin
```

***

## 2. CIS Benchmark Assessment

### Run kube-bench

kube-bench checks your cluster against the CIS Kubernetes Benchmark controls.

```bash
# Run against k3s
kube-bench --config-dir /etc/kube-bench/cfg --config /etc/kube-bench/cfg/config.yaml \
  run --targets node,policies

# Run against control plane
kube-bench run --targets master

# Output to JSON for processing
kube-bench run --json 2>/dev/null | jq '.Controls[] | {id, text, .tests[] | {result, .test_items[]}}'

# Save full report
kube-bench run > /tmp/cis_report.txt 2>&1
grep -E "FAIL|WARN|PASS" /tmp/cis_report.txt | head -50
```

### Run kubescape

kubescape scans against multiple security frameworks simultaneously.

```bash
# Scan against NSA + MITRE frameworks
kubescape scan framework nsa,mitre

# Scan a specific namespace
kubescape scan namespace default

# Scan all manifests in a directory
kubescape scan /vagrant/k8s/

# Generate HTML report
kubescape scan framework nsa --format html --output /tmp/kubescape_report.html

# Show only failed controls
kubescape scan framework nsa --severity-threshold medium --format pretty-printer
```

### Key CIS Controls for k3s

The most commonly failed controls and their fixes:

**Control 1.2.6 — Ensure anonymous auth is disabled**

```bash
# k3s disables anonymous auth by default
# Verify:
cat /etc/rancher/k3s/k3s.yaml | grep anonymous-auth
# Should not appear (defaults to false in k3s)
```

**Control 1.2.22 — Ensure audit logging is enabled**

```bash
# See Section 10 — Audit Logging
```

**Control 4.2.6 — Ensure --protect-kernel-defaults is set**

```bash
# Check current kubelet args
systemctl cat k3s | grep protect-kernel
```

***

## 3. RBAC — Role-Based Access Control

### Audit Current Permissions

```bash
# List all ClusterRoleBindings
kubectl get clusterrolebindings -o wide

# Who has cluster-admin?
kubectl get clusterrolebindings \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.roleRef.name}{"\t"}{range .subjects[*]}{.kind}/{.name}{" "}{end}{"\n"}{end}' \
  | grep cluster-admin

# List all RoleBindings in all namespaces
kubectl get rolebindings --all-namespaces -o wide

# Check what a specific service account can do
kubectl auth can-i --list --as=system:serviceaccount:default:default

# Check specific permission
kubectl auth can-i get secrets --as=system:serviceaccount:default:myapp
```

### Create Least-Privilege Service Accounts

Replace the default service account with dedicated accounts per workload.

```yaml
# Save as /tmp/rbac-readonly.yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-readonly
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: default
rules:
- apiGroups: [""]
  resources: ["pods", "configmaps"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pod-reader-binding
  namespace: default
subjects:
- kind: ServiceAccount
  name: app-readonly
  namespace: default
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

```bash
kubectl apply -f /tmp/rbac-readonly.yaml

# Verify the service account cannot do more than intended
kubectl auth can-i delete pods --as=system:serviceaccount:default:app-readonly
# Expected: no

kubectl auth can-i list pods --as=system:serviceaccount:default:app-readonly
# Expected: yes
```

### Restrict Default Service Account

The default service account in each namespace should not have API access.

```bash
# Patch default service account to prevent token automounting
kubectl patch serviceaccount default -n default \
  -p '{"automountServiceAccountToken": false}'

# Do the same for all namespaces
for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
  kubectl patch serviceaccount default -n $ns \
    -p '{"automountServiceAccountToken": false}' 2>/dev/null || true
done
```

### Remove Unnecessary ClusterRoleBindings

```bash
# List bindings to the edit and admin roles
kubectl get clusterrolebindings \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.roleRef.name}{"\n"}{end}' \
  | grep -E "\bedit\b|\badmin\b"

# Delete a binding that should not exist
kubectl delete clusterrolebinding BINDING_NAME
```

***

## 4. Network Policies

By default, all pods in a Kubernetes cluster can communicate with each other across namespaces. Network policies restrict this to only what is needed.

### Default Deny All Policy

Apply this to every namespace first, then explicitly allow only required traffic.

```yaml
# Save as /tmp/netpol-default-deny.yaml
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: default
spec:
  podSelector: {}       # Applies to all pods in namespace
  policyTypes:
  - Ingress
  - Egress
```

```bash
# Apply to key namespaces
for ns in default monitoring falco kyverno; do
  kubectl apply -f /tmp/netpol-default-deny.yaml -n $ns
done
```

### Allow Specific Traffic

```yaml
# Allow Prometheus to scrape metrics from pods in default namespace
# Save as /tmp/netpol-allow-monitoring.yaml
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-prometheus-scrape
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: monitoring
    ports:
    - protocol: TCP
      port: 8080
---
# Allow DNS resolution for all pods
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
```

```bash
kubectl apply -f /tmp/netpol-allow-monitoring.yaml
```

### Namespace Isolation

Prevent pods in one namespace from reaching pods in another.

```yaml
# Save as /tmp/netpol-namespace-isolation.yaml
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: namespace-isolation
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector: {}          # Allow from same namespace only
```

```bash
kubectl apply -f /tmp/netpol-namespace-isolation.yaml

# Verify network policy is applied
kubectl get networkpolicies --all-namespaces
kubectl describe networkpolicy default-deny-all
```

***

## 5. Pod Security Standards

Kubernetes Pod Security Standards replace the deprecated PodSecurityPolicy. Three levels: Privileged, Baseline, Restricted.

### Enable Pod Security Admission

```bash
# Label a namespace for restricted enforcement
kubectl label namespace default \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/enforce-version=latest \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/warn-version=latest \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/audit-version=latest

# Label monitoring namespace as baseline (Prometheus needs more permissions)
kubectl label namespace monitoring \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/warn=restricted
```

### Compliant Pod Manifest

```yaml
# Save as /tmp/pod-restricted.yaml
---
apiVersion: v1
kind: Pod
metadata:
  name: secure-app
  namespace: default
spec:
  automountServiceAccountToken: false
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: MASTER_IP:30001/airgap/nginx:alpine
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
        - ALL
    resources:
      requests:
        memory: "64Mi"
        cpu: "100m"
      limits:
        memory: "128Mi"
        cpu: "200m"
    volumeMounts:
    - name: tmp
      mountPath: /tmp
  volumes:
  - name: tmp
    emptyDir: {}
```

### Static Analysis with kube-score

```bash
# Check a manifest before applying
kube-score score /tmp/pod-restricted.yaml

# Check all manifests in a directory
kube-score score /vagrant/k8s/*.yaml

# Output as JSON
kube-score score --output-format json /tmp/pod-restricted.yaml | jq '.[] | {name, checks: [.checks[] | select(.grade < 5)]}'
```

***

## 6. Falco Runtime Security

Falco monitors syscalls and Kubernetes audit events at runtime and alerts on suspicious behavior.

### Verify Falco is Running

```bash
# Check pod status
kubectl get pods -n falco

# View recent alerts
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=50

# Falco config
kubectl get configmap -n falco
```

### Key Built-In Rules to Know

```bash
# View all active rules
kubectl exec -n falco -l app.kubernetes.io/name=falco -- \
  falco --list-rules 2>/dev/null | head -40

# Trigger a test alert (shell in a container — always detected)
kubectl run test --image=MASTER_IP:30001/airgap/alpine:3.20 \
  --restart=Never -- sh -c "ls /etc/shadow" 2>/dev/null || true

# Watch for the alert in real time
kubectl logs -n falco -l app.kubernetes.io/name=falco -f
```

### Custom Falco Rules

Create rules that match your lab's specific workloads.

```yaml
# Save as /tmp/custom-falco-rules.yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: custom-falco-rules
  namespace: falco
data:
  custom_rules.yaml: |
    # Alert on any write to /etc in a container
    - rule: Write to /etc in container
      desc: Detects any write to /etc directory in a running container
      condition: >
        container and
        (evt.type = open or evt.type = openat) and
        evt.is_open_write = true and
        fd.name startswith /etc
      output: >
        File opened for writing in /etc (user=%user.name
        command=%proc.cmdline file=%fd.name container=%container.id
        image=%container.image.repository)
      priority: WARNING
      tags: [container, filesystem, mitre_persistence]

    # Alert on curl or wget inside containers
    - rule: Outbound Network Tool in Container
      desc: Detects use of curl or wget from inside a container
      condition: >
        container and
        proc.name in (curl, wget, nc, ncat, netcat) and
        not proc.pname in (containerd-shim, runc)
      output: >
        Network tool executed in container (user=%user.name
        command=%proc.cmdline container=%container.id
        image=%container.image.repository)
      priority: NOTICE
      tags: [container, network, mitre_exfiltration]

    # Alert on privilege escalation attempts
    - rule: Setuid/Setgid Binary Execution
      desc: Detects execution of setuid or setgid binaries in containers
      condition: >
        container and
        (proc.is_suid_exe = true or proc.is_sgid_exe = true) and
        not proc.name in (su, sudo, newgrp)
      output: >
        Setuid binary executed (user=%user.name binary=%proc.name
        command=%proc.cmdline container=%container.id)
      priority: WARNING
      tags: [container, privilege_escalation]

    # Alert on Kubernetes API access from pods
    - rule: Pod Accessing K8s API
      desc: Pod is directly accessing the Kubernetes API server
      condition: >
        evt.type = connect and
        container and
        fd.sip = "10.43.0.1" and
        fd.sport = 443 and
        not k8s.ns.name in (kube-system, falco, kyverno, cert-manager)
      output: >
        Pod accessing Kubernetes API (pod=%k8s.pod.name
        namespace=%k8s.ns.name container=%container.id
        image=%container.image.repository)
      priority: NOTICE
      tags: [k8s, lateral_movement]
```

```bash
kubectl apply -f /tmp/custom-falco-rules.yaml

# Reload Falco to pick up new rules
kubectl rollout restart daemonset/falco -n falco

# Wait for rollout
kubectl rollout status daemonset/falco -n falco
```

### Harbor Registry Abuse Detection

```yaml
    # Detect pulls from registries other than Harbor
    - rule: Unauthorized Registry Pull
      desc: Container image pulled from registry other than Harbor
      condition: >
        container.image.repository != "" and
        not container.image.repository startswith "MASTER_IP:30001"
      output: >
        Container pulled from unauthorized registry
        (image=%container.image.repository tag=%container.image.tag
        container=%container.id pod=%k8s.pod.name)
      priority: WARNING
      tags: [container, supply_chain]
```

***

## 7. Kyverno Policy Enforcement

Kyverno enforces policies at admission time, before any resource is created or modified in the cluster.

### Verify Kyverno is Running

```bash
kubectl get pods -n kyverno
kubectl get clusterpolicies
```

### Require Non-Root Containers

```yaml
# Save as /tmp/kyverno-nonroot.yaml
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-non-root-containers
  annotations:
    policies.kyverno.io/title: Require Non-Root Containers
    policies.kyverno.io/category: Pod Security
    policies.kyverno.io/severity: medium
    policies.kyverno.io/description: >
      Containers must not run as root. This prevents container
      escape attacks from having host root access.
spec:
  validationFailureAction: Enforce
  background: true
  rules:
  - name: check-runasnonroot
    match:
      any:
      - resources:
          kinds:
          - Pod
    validate:
      message: "Containers must not run as root. Set securityContext.runAsNonRoot: true"
      pattern:
        spec:
          =(initContainers):
          - =(securityContext):
              =(runAsNonRoot): "true"
          containers:
          - securityContext:
              runAsNonRoot: true
```

### Disallow Privileged Containers

```yaml
# Save as /tmp/kyverno-no-privileged.yaml
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-privileged-containers
  annotations:
    policies.kyverno.io/title: Disallow Privileged Containers
    policies.kyverno.io/severity: high
spec:
  validationFailureAction: Enforce
  background: true
  rules:
  - name: no-privileged
    match:
      any:
      - resources:
          kinds:
          - Pod
    validate:
      message: "Privileged containers are not allowed."
      pattern:
        spec:
          =(initContainers):
          - =(securityContext):
              =(privileged): "false"
          containers:
          - =(securityContext):
              =(privileged): "false"
```

### Require Resource Limits

```yaml
# Save as /tmp/kyverno-resource-limits.yaml
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-resource-limits
  annotations:
    policies.kyverno.io/title: Require Resource Limits
    policies.kyverno.io/severity: medium
spec:
  validationFailureAction: Enforce
  background: true
  rules:
  - name: check-limits
    match:
      any:
      - resources:
          kinds:
          - Pod
    validate:
      message: "CPU and memory limits are required for all containers."
      pattern:
        spec:
          containers:
          - resources:
              limits:
                memory: "?*"
                cpu: "?*"
```

### Disallow Latest Image Tag

```yaml
# Save as /tmp/kyverno-no-latest.yaml
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-latest-tag
  annotations:
    policies.kyverno.io/title: Disallow Latest Tag
    policies.kyverno.io/severity: medium
spec:
  validationFailureAction: Enforce
  background: true
  rules:
  - name: no-latest-tag
    match:
      any:
      - resources:
          kinds:
          - Pod
    validate:
      message: "Using ':latest' tag is not allowed. Pin to a specific version."
      foreach:
      - list: "request.object.spec.containers"
        deny:
          conditions:
            any:
            - key: "{{ element.image }}"
              operator: Equals
              value: "*:latest"
            - key: "{{ element.image }}"
              operator: NotContains
              value: ":"
```

### Require Harbor Registry

```yaml
# Save as /tmp/kyverno-require-harbor.yaml
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-harbor-registry
  annotations:
    policies.kyverno.io/title: Require Harbor Registry
    policies.kyverno.io/severity: high
spec:
  validationFailureAction: Enforce
  background: false
  rules:
  - name: check-registry
    match:
      any:
      - resources:
          kinds:
          - Pod
    exclude:
      any:
      - resources:
          namespaces:
          - kube-system
          - falco
          - kyverno
          - cert-manager
    validate:
      message: "Images must be pulled from the Harbor registry (MASTER_IP:30001)."
      foreach:
      - list: "request.object.spec.containers"
        deny:
          conditions:
            all:
            - key: "{{ element.image }}"
              operator: NotContains
              value: "30001"
```

### Apply All Policies

```bash
kubectl apply -f /tmp/kyverno-nonroot.yaml
kubectl apply -f /tmp/kyverno-no-privileged.yaml
kubectl apply -f /tmp/kyverno-resource-limits.yaml
kubectl apply -f /tmp/kyverno-no-latest.yaml
kubectl apply -f /tmp/kyverno-require-harbor.yaml

# Verify policies are active
kubectl get clusterpolicies

# Test enforcement (should be rejected)
kubectl run test-root \
  --image=MASTER_IP:30001/airgap/nginx:alpine \
  --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"test","image":"MASTER_IP:30001/airgap/nginx:alpine","securityContext":{"runAsUser":0}}]}}'

# Check policy reports
kubectl get policyreports --all-namespaces
kubectl describe policyreport -n default
```

***

## 8. Secrets Management

### Audit Existing Secrets

```bash
# List all secrets
kubectl get secrets --all-namespaces

# Find secrets stored as plain environment variables (bad practice)
kubectl get pods --all-namespaces -o json | \
  jq '.items[].spec.containers[].env[]? | select(.value != null) | .name' | \
  grep -iE "pass|token|key|secret|cred"

# Check for secrets mounted as environment variables from secretKeyRef
kubectl get pods --all-namespaces -o json | \
  jq '.items[].spec.containers[].env[]? | select(.valueFrom.secretKeyRef != null) | .name'
```

### Encrypt Secrets at Rest

k3s does not encrypt secrets at rest by default. Enable encryption:

```bash
# Create encryption config
cat > /tmp/encryption-config.yaml << 'ENCEOF'
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
- resources:
  - secrets
  providers:
  - aescbc:
      keys:
      - name: key1
        secret: $(head -c 32 /dev/urandom | base64)
  - identity: {}
ENCEOF

# Copy to k3s config directory
sudo cp /tmp/encryption-config.yaml /etc/rancher/k3s/encryption-config.yaml

# Add to k3s server args
# Edit /etc/systemd/system/k3s.service and add:
# --kube-apiserver-arg=encryption-provider-config=/etc/rancher/k3s/encryption-config.yaml

sudo systemctl daemon-reload
sudo systemctl restart k3s

# Verify encryption is active
kubectl get secrets --all-namespaces -o json | \
  kubectl replace -f - 2>/dev/null   # Re-encrypt all secrets
```

### Use External Secrets

For production-like setups, use a secrets manager instead of Kubernetes secrets.

```bash
# Install External Secrets Operator
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets \
  external-secrets/external-secrets \
  -n external-secrets \
  --create-namespace
```

***

## 9. Image Security with Harbor and Trivy

### Enable Trivy Scanning in Harbor

```bash
# Access Harbor at https://MASTER_IP:30001
# Admin → Interrogation Services → Trivy → Enable

# Scan a specific image via Harbor API
curl -sk -u admin:HARBOR_PASS \
  -X POST "https://MASTER_IP:30001/api/v2.0/projects/airgap/repositories/busybox/artifacts/1.36/scan"

# Get scan results
curl -sk -u admin:HARBOR_PASS \
  "https://MASTER_IP:30001/api/v2.0/projects/airgap/repositories/busybox/artifacts/1.36/additions/vulnerabilities" \
  | jq '."application/vnd.security.vulnerability.report; version=1.1".vulnerabilities | length'
```

### Scan Images with Trivy Directly

```bash
# Scan an image from Harbor
trivy image --insecure MASTER_IP:30001/airgap/nginx:alpine

# Scan only critical and high vulnerabilities
trivy image --severity CRITICAL,HIGH MASTER_IP:30001/airgap/nginx:alpine

# Scan a running pod's image
POD_IMAGE=$(kubectl get pod -n monitoring -l app.kubernetes.io/name=grafana \
  -o jsonpath='{.items[0].spec.containers[0].image}')
trivy image --insecure $POD_IMAGE

# Scan a Kubernetes manifest for misconfigurations
trivy config /vagrant/k8s/

# Output SARIF for integration
trivy image --format sarif --output /tmp/scan.sarif \
  MASTER_IP:30001/airgap/nginx:alpine
```

### Set Vulnerability Threshold in Kyverno

```yaml
# Block pods using images with critical vulnerabilities
# (Requires image scanning results to be available)
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: block-vulnerable-images
spec:
  validationFailureAction: Enforce
  rules:
  - name: check-image-vulnerability
    match:
      any:
      - resources:
          kinds:
          - Pod
    verifyImages:
    - imageReferences:
      - "MASTER_IP:30001/*"
      attestors:
      - count: 1
        entries:
        - keys:
            publicKeys: |-
              YOUR_COSIGN_PUBLIC_KEY
```

***

## 10. Audit Logging

### Enable Kubernetes Audit Logging in k3s

```bash
# Create audit policy
cat > /etc/rancher/k3s/audit-policy.yaml << 'AUDITEOF'
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
# Log secret access at request and response level
- level: RequestResponse
  resources:
  - group: ""
    resources: ["secrets"]

# Log pod exec, attach, portforward
- level: Request
  verbs: ["exec", "attach", "portforward"]
  resources:
  - group: ""
    resources: ["pods"]

# Log authentication failures
- level: Metadata
  omitStages:
  - RequestReceived
  resources:
  - group: ""
    resources: ["users", "groups", "serviceaccounts"]

# Log all other requests at metadata level
- level: Metadata
  omitStages:
  - RequestReceived
AUDITEOF

# Add to k3s server configuration
# Edit /etc/systemd/system/k3s.service, add to ExecStart:
# --kube-apiserver-arg=audit-log-path=/var/log/k3s-audit.log \
# --kube-apiserver-arg=audit-policy-file=/etc/rancher/k3s/audit-policy.yaml \
# --kube-apiserver-arg=audit-log-maxage=30 \
# --kube-apiserver-arg=audit-log-maxbackup=10 \
# --kube-apiserver-arg=audit-log-maxsize=100

sudo systemctl daemon-reload
sudo systemctl restart k3s

# Verify audit log is being written
tail -f /var/log/k3s-audit.log | jq '.'
```

### Query Audit Logs

```bash
# Find all secret reads
cat /var/log/k3s-audit.log | jq \
  'select(.objectRef.resource == "secrets" and .verb == "get") |
   {user: .user.username, secret: .objectRef.name, namespace: .objectRef.namespace, time: .requestReceivedTimestamp}'

# Find all exec events (interactive shell access)
cat /var/log/k3s-audit.log | jq \
  'select(.verb == "exec") |
   {user: .user.username, pod: .objectRef.name, namespace: .objectRef.namespace, time: .requestReceivedTimestamp}'

# Find failed authentications
cat /var/log/k3s-audit.log | jq \
  'select(.responseStatus.code == 401 or .responseStatus.code == 403) |
   {user: .user.username, verb: .verb, resource: .objectRef.resource, code: .responseStatus.code}'
```

***

## 11. Cert-Manager TLS Hardening

### Verify Cert-Manager is Running

```bash
kubectl get pods -n cert-manager
kubectl get certificates --all-namespaces
kubectl get certificaterequests --all-namespaces
```

### Create a Self-Signed Issuer

```yaml
# Save as /tmp/cert-issuer.yaml
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
---
# Internal CA issuer
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: lab-ca-issuer
spec:
  ca:
    secretName: lab-ca-secret
```

```bash
kubectl apply -f /tmp/cert-issuer.yaml
```

### Issue a Certificate

```yaml
# Save as /tmp/cert-example.yaml
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: grafana-tls
  namespace: monitoring
spec:
  secretName: grafana-tls-secret
  duration: 2160h   # 90 days
  renewBefore: 360h # Renew 15 days before expiry
  isCA: false
  privateKey:
    algorithm: ECDSA
    size: 256
  usages:
  - server auth
  - client auth
  dnsNames:
  - grafana.local
  - grafana.monitoring.svc.cluster.local
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
```

```bash
kubectl apply -f /tmp/cert-example.yaml

# Monitor certificate status
kubectl get certificate -n monitoring
kubectl describe certificate grafana-tls -n monitoring

# Certificate should show: Ready = True
```

***

## 12. Node Hardening

### Check Node Security Posture

```bash
# Check what is running on the node
vagrant ssh devops-1

# Kernel version and security features
uname -r
cat /proc/sys/kernel/dmesg_restrict
cat /proc/sys/kernel/kptr_restrict

# Check AppArmor
sudo aa-status

# Check seccomp support
grep SECCOMP /boot/config-$(uname -r) 2>/dev/null

# Running services
systemctl list-units --type=service --state=running

# Open ports
ss -tlnp

# SUID binaries (potential privilege escalation paths)
find / -perm -4000 -type f 2>/dev/null | sort
```

### Harden the Node OS

```bash
# Disable core dumps
echo "* hard core 0" >> /etc/security/limits.conf
echo "fs.suid_dumpable = 0" >> /etc/sysctl.d/99-hardening.conf
sysctl -p /etc/sysctl.d/99-hardening.conf

# Restrict dmesg
echo "kernel.dmesg_restrict = 1" >> /etc/sysctl.d/99-hardening.conf

# Disable IPv6 if not needed
echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.d/99-hardening.conf

# Enable SYN flood protection
echo "net.ipv4.tcp_syncookies = 1" >> /etc/sysctl.d/99-hardening.conf

# Apply
sysctl --system

# Disable unnecessary services
sudo systemctl disable --now avahi-daemon cups bluetooth 2>/dev/null || true
```

### etcd Security

k3s uses a built-in SQLite datastore by default. Verify it is not exposed:

```bash
# etcd/datastore should only listen on localhost
ss -tlnp | grep 2379

# k3s datastore file permissions
ls -la /var/lib/rancher/k3s/server/db/
# Should be readable only by root
```

***

## 13. Hardening Verification Checklist

### RBAC

```bash
# No anonymous access to the API
kubectl auth can-i get pods --as=system:anonymous 2>/dev/null
# Expected: no

# Default service accounts cannot access API
kubectl auth can-i get secrets \
  --as=system:serviceaccount:default:default 2>/dev/null
# Expected: no

# No unexpected cluster-admin bindings
kubectl get clusterrolebindings -o json | \
  jq '.items[] | select(.roleRef.name == "cluster-admin") | .metadata.name'
```

### Network Policies

```bash
# Network policies exist in key namespaces
kubectl get networkpolicies --all-namespaces
# Should show policies in default, monitoring, falco, kyverno

# Test isolation (run from a test pod)
kubectl run nettest --image=MASTER_IP:30001/airgap/busybox:1.36 \
  --restart=Never -- sh -c "wget -qO- http://kube-apiserver:443" 2>/dev/null
# Expected: connection refused or timeout
kubectl delete pod nettest --force
```

### Pod Security

```bash
# No privileged pods running
kubectl get pods --all-namespaces -o json | \
  jq '.items[] | select(.spec.containers[].securityContext.privileged == true) |
      {name: .metadata.name, namespace: .metadata.namespace}'
# Expected: empty

# No pods running as root
kubectl get pods --all-namespaces -o json | \
  jq '.items[] | select(.spec.containers[].securityContext.runAsUser == 0) |
      {name: .metadata.name, namespace: .metadata.namespace}'
# Expected: only system/infrastructure pods
```

### Falco

```bash
# Falco is running and alerting
kubectl get pods -n falco
# Expected: Running

# Trigger a test alert and verify it is captured
kubectl exec -n default -it nettest -- sh 2>/dev/null || true
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=5
# Expected: rule match for terminal shell or similar
```

### Kyverno Policies

```bash
# All policies are active
kubectl get clusterpolicies
# Expected: require-non-root-containers, disallow-privileged-containers, etc.

# Test enforcement
kubectl run priv-test \
  --image=MASTER_IP:30001/airgap/alpine:3.20 \
  --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"t","image":"MASTER_IP:30001/airgap/alpine:3.20","securityContext":{"privileged":true}}]}}' 2>&1
# Expected: Error from server (admission webhook denied)
```

### Secrets

```bash
# No secrets in plain environment variables
kubectl get pods --all-namespaces -o json | \
  jq '[.items[].spec.containers[].env[]? |
       select(.value != null) |
       select(.name | test("PASS|TOKEN|KEY|SECRET|CRED"; "i"))] | length'
# Expected: 0
```

### Images

```bash
# All images come from Harbor
kubectl get pods --all-namespaces -o json | \
  jq -r '.items[].spec.containers[].image' | sort -u | \
  grep -v "MASTER_IP:30001"
# Expected: empty (system images from k3s are exceptions)

# No images using :latest tag
kubectl get pods --all-namespaces -o json | \
  jq -r '.items[].spec.containers[].image' | grep ":latest"
# Expected: empty
```

***

## Disclaimer

Apply hardening controls progressively in a lab environment. Some controls, especially privileged pod denial and root container denial, can break system pods if applied globally. Always exclude `kube-system` and security tool namespaces from restrictive policies, and test in a non-critical namespace before applying cluster-wide.

All hardening in this guide is for the isolated lab environment in `labs/infrastructure/devops-linux-lab/`.
