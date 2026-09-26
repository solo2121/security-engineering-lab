# Security Hardening Guide

## Kubernetes RBAC

### Create Service Accounts

```bash
kubectl create namespace lab-apps
kubectl create serviceaccount lab-deployer -n lab-apps

kubectl create role lab-deployer \
  --verb=get,list,watch,create,update,patch \
  --resource=pods,deployments,services \
  -n lab-apps

kubectl create rolebinding lab-deployer \
  --role=lab-deployer \
  --serviceaccount=lab-apps:lab-deployer \
  -n lab-apps
```

### Default Deny Network Policy

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: lab-apps
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
***
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-intra-ns
  namespace: lab-apps
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector: {}
```

---

## Pod Security Standards

PodSecurityPolicy is deprecated and removed in newer Kubernetes versions. Use Pod Security Admission or Kyverno instead.

### Example Restricted Namespace Labels

```bash
kubectl label namespace lab-apps \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/warn=restricted
```

### Example Restricted Pod Spec

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: restricted-example
  namespace: lab-apps
spec:
  securityContext:
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: nginx:stable
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
        - ALL
```

---

## Kubernetes Audit Logging

### Enable Audit Logs

```bash
sudo tee /etc/kubernetes/audit-policy.yaml << 'EOF'
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
- level: Metadata
  omitStages:
  - RequestReceived
EOF
```

Update the kube-apiserver manifest to include:

```bash
--audit-log-path=/var/log/kubernetes/audit.log
--audit-policy-file=/etc/kubernetes/audit-policy.yaml
```

### View Audit Logs

```bash
sudo tail -f /var/log/kubernetes/audit.log | jq .
```

---

## Secrets Management

### Use Encrypted Secrets

```bash
head -c 32 /dev/urandom | base64
```

Example encryption configuration:

```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
- resources:
  - secrets
  providers:
  - aescbc:
      keys:
      - name: key1
        secret: <BASE64-ENCODED-KEY>
  - identity: {}
```

### Create and Access Secrets

```bash
kubectl create secret generic db-password \
  --from-literal=password=secure-passphrase \
  -n lab-apps

kubectl set env deployment/app --from=secret/db-password -n lab-apps

kubectl get secret db-password -o jsonpath='{.data.password}' | base64 -d
```

---

## TLS and SSL

### Generate Self-Signed Certificates

```bash
openssl genrsa -out ca.key 2048
openssl req -new -x509 -days 365 -key ca.key -out ca.crt

openssl genrsa -out server.key 2048
openssl req -new -key server.key -out server.csr
openssl x509 -req -days 365 -in server.csr \
  -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt

kubectl create secret tls lab-tls \
  --cert=server.crt --key=server.key \
  -n lab-apps
```

### Ingress with TLS

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: secure-ingress
  namespace: lab-apps
spec:
  tls:
  - hosts:
    - app.lab.local
    secretName: lab-tls
  rules:
  - host: app.lab.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app-service
            port:
              number: 443
```

---

## Image Security

### Container Image Scanning

```bash
trivy image nginx:latest
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image docker://myapp:latest
```

### Image Pull Policies

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-pod
spec:
  containers:
  - name: app
    image: myregistry.azurecr.io/app:v1.0.0
    imagePullPolicy: Always
  imagePullSecrets:
  - name: registry-credentials
```

---

## Host-Level Security

### SELinux Configuration

```bash
getenforce
sudo setenforce 1
sudo nano /etc/selinux/config
# SELINUX=enforcing
```

### Firewall Rules

```bash
sudo ufw enable
sudo ufw allow 6443/tcp
sudo ufw allow 10250/tcp
sudo ufw allow 30000:32767/tcp
```

### SSH Hardening

```bash
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart sshd
```

---

## Monitoring and Auditing

### Enable Falco

```bash
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm install falco falcosecurity/falco --set falco.grpc.enabled=true
kubectl logs -n falco -l app=falco -f
```

### Prometheus Alerting

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-alerts
data:
  prometheus-alerts.yaml: |
    groups:
    - name: security
      rules:
      - alert: UnauthorizedAPIAccess
        expr: apiserver_audit_event_total{user_verb=~"delete|patch"} > 5
        for: 1m
```

---

## Compliance Checklist

- [ ] RBAC roles are defined for all service accounts.
- [ ] Network policies are enforced with a default-deny baseline.
- [ ] Pod Security Admission or Kyverno is configured.
- [ ] Secrets are encrypted at rest.
- [ ] TLS is enabled for sensitive service traffic.
- [ ] Image scanning is enabled in CI/CD.
- [ ] Audit logging is configured.
- [ ] Host firewall rules are applied.
- [ ] SSH hardening is applied.
- [ ] Runtime monitoring with Falco is enabled.

---

**Last Updated:** June 27 2026
