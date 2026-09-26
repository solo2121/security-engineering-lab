# DevOps / DevSecOps Lab — Practical Guide

**Lab version:** 8.2.0  
**Author:** Miguel A. Carlo

---

## Table of Contents

1. [Lab Setup and First Boot](#1-lab-setup-and-first-boot)
2. [Kubernetes — k3s Cluster](#2-kubernetes--k3s-cluster)
3. [Harbor — Container Registry](#3-harbor--container-registry)
4. [Argo CD — GitOps Platform](#4-argo-cd--gitops-platform)
5. [Prometheus and Grafana — Observability](#5-prometheus-and-grafana--observability)
6. [Falco — Runtime Security](#6-falco--runtime-security)
7. [Kyverno — Policy Enforcement](#7-kyverno--policy-enforcement)
8. [Cert-Manager — TLS Automation](#8-cert-manager--tls-automation)
9. [Terraform and OpenTofu — Infrastructure as Code](#9-terraform-and-opentofu--infrastructure-as-code)
10. [Kind Lab — Kubernetes in Docker](#10-kind-lab--kubernetes-in-docker)
11. [K3d Lab — K3s in Docker](#11-k3d-lab--k3s-in-docker)
12. [Linux Practice Nodes](#12-linux-practice-nodes)
13. [Ansible — Configuration Management](#13-ansible--configuration-management)
14. [Day-2 Operations Tools](#14-day-2-operations-tools)
15. [Lab Validation](#15-lab-validation)
16. [Common Workflows](#16-common-workflows)
17. [CI/CD Server](#17-cicd-server)

---

## Lab Reference

### VM Inventory

| VM | Typical IP | Role | Memory | CPUs |
|----|-----------|------|--------|------|
| devops-1 | .114 | k3s control plane and all services | 8192 MB | 4 |
| worker-1 | .11 | k3s worker agent | 2048 MB | 2 |
| worker-2 | .12 | k3s worker agent | 2048 MB | 2 |
| kind-lab | .200 | Kind cluster inside Docker | 4096 MB | 2 |
| k3d-lab | .201 | K3d cluster inside Docker | 4096 MB | 2 |
| ubuntu-lab | .20 | Ubuntu 24.04 practice node | 1024 MB | 1 |
| rocky-lab | .21 | Rocky Linux 10 practice node | 1024 MB | 1 |
| alma-lab | .22 | AlmaLinux 10 practice node | 1024 MB | 1 |
| suse-lab | .23 | openSUSE Leap 15.6 practice node | 1024 MB | 1 |
| node1 | .30 | Ansible managed node | 1024 MB | 1 |
| node2 | .31 | Ansible managed node | 1024 MB | 1 |
| cicd-server | .50 | Gitea + Jenkins + SonarQube + Vault + ZAP | 4096 MB | 2 |

IPs are based on the libvirt network. The actual `MASTER_IP` is printed at `vagrant up` time.

### Tool Versions

| Tool | Version |
|------|---------|
| k3s | v1.31.4+k3s1 |
| Docker | 27.3.1 |
| Harbor | Chart 1.14.0 |
| Argo CD | 7.7.5 |
| Prometheus Stack | 68.3.0 |
| Falco | 2.3.0 |
| Kyverno | 3.3.7 |
| Cert-Manager | 1.16.2 |
| Terraform | 1.9.8 |
| OpenTofu | 1.8.0 |
| Kind | v0.24.0 |
| K3d | v5.7.5 |
| Ingress NGINX | v1.11.3 |
| Gitea | 1.24.3 |
| Jenkins | 2.516.2-lts-jdk17 |
| SonarQube | 25.7 |
| HashiCorp Vault | 1.18.2 |
| OWASP ZAP | 2.16.1 |
| Gitleaks | 8.18.4 |
| Trivy (CI/CD host) | 0.57.1 |

### Service Access

| Service | URL | Credentials |
|---------|-----|-------------|
| Harbor | `https://MASTER_IP:30001` | `admin` / your `HARBOR_PASS` |
| Argo CD | `https://MASTER_IP:30003` | `admin` / see `argocd-initial-admin-secret` |
| Grafana | `https://MASTER_IP:<auto-port>` | `admin` / `admin` |
| k3s API | `https://MASTER_IP:16443` | kubeconfig at `/vagrant/kubeconfig.yaml` |
| Gitea | `http://localhost:3000` | Set on first visit |
| Jenkins | `http://localhost:8080` | See section 17 for the initial admin password |
| SonarQube | `http://localhost:9000` | `admin` / `admin` |
| Vault | `http://localhost:8200` | token: `root` (dev mode) |
| OWASP ZAP | `http://localhost:8090` | — |

---

## 1. Lab Setup and First Boot

### Set Harbor Password

```bash
export HARBOR_PASS='YourStrongPassword'
```

### Choose a Deployment Profile

```bash
LAB_PROFILE=minimal vagrant up
LAB_PROFILE=dev vagrant up
LAB_PROFILE=full vagrant up
START_VMS=devops-1,worker-1,kind-lab vagrant up
```

### Use the Lab Manager

```bash
python3 ./scripts/vagrant_manager.py
```

### Verify the Lab Is Ready

```bash
vagrant ssh devops-1

kubectl get nodes -o wide
kubectl get pods -A | grep -v Running

curl -sk https://MASTER_IP:30001/api/v2.0/health | jq .status
kubectl get pods -n argocd

exit
./scripts/validate-lab.sh
```

---

## 2. Kubernetes — k3s Cluster

### Basic Cluster Operations

```bash
vagrant ssh devops-1

kubectl get nodes -o wide
kubectl describe node devops-1
kubectl describe node worker-1

kubectl cluster-info
kubectl version

kubectl top nodes
kubectl top pods -A
```

### Working with Namespaces

```bash
kubectl get namespaces
kubectl get pods -n harbor
kubectl get pods -n argocd
kubectl get pods -n monitoring
kubectl get pods -n falco
kubectl get pods -n kyverno
kubectl get pods -n cert-manager
kubectl get pods -n ingress-nginx
```

### Deploy a Test Workload

```bash
kubectl run nginx-test \
  --image=MASTER_IP:30001/airgap/nginx:alpine \
  --port=80

kubectl describe pod nginx-test | grep "Image:"

kubectl expose pod nginx-test \
  --type=NodePort --port=80

kubectl get svc nginx-test

kubectl delete pod nginx-test
kubectl delete svc nginx-test
```

### Deploy via YAML

```bash
cat > /tmp/test-deploy.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-test
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web-test
  template:
    metadata:
      labels:
        app: web-test
    spec:
      containers:
      - name: nginx
        image: MASTER_IP:30001/airgap/nginx:alpine
        ports:
        - containerPort: 80
***
apiVersion: v1
kind: Service
metadata:
  name: web-test
spec:
  selector:
    app: web-test
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
EOF

kubectl apply -f /tmp/test-deploy.yaml
kubectl get pods -l app=web-test
kubectl get svc web-test

kubectl run curl-test --image=MASTER_IP:30001/airgap/alpine:3.20 \
  --rm -it --restart=Never -- \
  wget -qO- http://web-test

kubectl delete -f /tmp/test-deploy.yaml
```

### Ingress

```bash
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx

cat > /tmp/test-ingress.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web-test-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: web-test.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-test
            port:
              number: 80
EOF

kubectl apply -f /tmp/test-ingress.yaml
kubectl get ingress

curl -H "Host: web-test.local" http://localhost:8080
```

### Persistent Storage

```bash
kubectl get storageclass

cat > /tmp/test-pvc.yaml << 'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF

kubectl apply -f /tmp/test-pvc.yaml
kubectl get pvc
kubectl describe pvc test-pvc

kubectl delete pvc test-pvc
```

### RBAC Practice

```bash
kubectl create serviceaccount dev-user -n default

cat > /tmp/pod-reader-role.yaml << 'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: default
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
EOF

kubectl apply -f /tmp/pod-reader-role.yaml

kubectl create rolebinding dev-pod-reader \
  --role=pod-reader \
  --serviceaccount=default:dev-user \
  -n default

kubectl auth can-i list pods \
  --as=system:serviceaccount:default:dev-user

kubectl auth can-i delete pods \
  --as=system:serviceaccount:default:dev-user

kubectl delete rolebinding dev-pod-reader
kubectl delete role pod-reader
kubectl delete serviceaccount dev-user
```

---

## 3. Harbor — Container Registry

Harbor is accessible at `https://MASTER_IP:30001`. All images are pre-seeded in the `airgap` project. The k3s cluster pulls images through Harbor automatically via `registries.yaml`.

### Log In

```bash
docker login MASTER_IP:30001 -u admin -p "$HARBOR_PASS"
docker login MASTER_IP:30001 -u admin -p <your_harbor_pass>
```

### Browse Projects and Images via CLI

```bash
HARBOR_URL=https://MASTER_IP:30001
HARBOR_AUTH="admin:$HARBOR_PASS"

curl -sk -u "$HARBOR_AUTH" \
  "$HARBOR_URL/api/v2.0/projects" | jq '.[].name'

curl -sk -u "$HARBOR_AUTH" \
  "$HARBOR_URL/api/v2.0/projects/airgap/repositories" \
  | jq '.[].name'

curl -sk -u "$HARBOR_AUTH" \
  "$HARBOR_URL/api/v2.0/projects/airgap/repositories/nginx/artifacts" \
  | jq '.[].tags[].name'
```

### Push a Custom Image to Harbor

```bash
cat > /tmp/Dockerfile.test << 'EOF'
FROM alpine:3.20
RUN echo "Custom lab image" > /hello.txt
CMD ["cat", "/hello.txt"]
EOF

docker build -t my-app:1.0 -f /tmp/Dockerfile.test /tmp
docker tag my-app:1.0 MASTER_IP:30001/airgap/my-app:1.0
docker push MASTER_IP:30001/airgap/my-app:1.0

kubectl run my-app \
  --image=MASTER_IP:30001/airgap/my-app:1.0 \
  --restart=Never

kubectl logs my-app
kubectl delete pod my-app
```

### Enable Trivy Vulnerability Scanning

```bash
curl -sk -u "$HARBOR_AUTH" \
  -X PUT \
  -H "Content-Type: application/json" \
  -d '{"auto_scan": true}' \
  "$HARBOR_URL/api/v2.0/projects/airgap"

curl -sk -u "$HARBOR_AUTH" \
  -X POST \
  "$HARBOR_URL/api/v2.0/projects/airgap/repositories/nginx/artifacts/alpine/scan"
```

---

## 4. Argo CD — GitOps Platform

Argo CD is accessible at `https://MASTER_IP:30003`.

### Get the Admin Password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
echo
```

### Log In via CLI

```bash
curl -sSL -o /usr/local/bin/argocd \
  https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd

argocd login MASTER_IP:30003 \
  --username admin \
  --password <PASSWORD_FROM_ABOVE> \
  --insecure

argocd cluster list
```

### Deploy an Application from Git

```bash
argocd app create guestbook \
  --repo https://github.com/argoproj/argocd-example-apps.git \
  --path guestbook \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default

argocd app sync guestbook
argocd app get guestbook
argocd app wait guestbook --health
kubectl get pods -n default -l app=guestbook-ui
argocd app delete guestbook
```

### Configure Automated Sync with Self-Healing

```bash
argocd app set guestbook \
  --sync-policy automated \
  --self-heal \
  --auto-prune

kubectl delete pod -l app=guestbook-ui
argocd app get guestbook
```

### Create an ApplicationSet

```bash
cat > /tmp/appset.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: lab-apps
  namespace: argocd
spec:
  generators:
  - list:
      elements:
      - env: dev
        namespace: dev
      - env: staging
        namespace: staging
  template:
    metadata:
      name: '{{env}}-guestbook'
    spec:
      project: default
      source:
        repoURL: https://github.com/argoproj/argocd-example-apps.git
        targetRevision: HEAD
        path: guestbook
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{namespace}}'
      syncPolicy:
        syncOptions:
        - CreateNamespace=true
EOF

kubectl apply -f /tmp/appset.yaml
kubectl get applications -n argocd
kubectl delete -f /tmp/appset.yaml
```

---

## 5. Prometheus and Grafana — Observability

### Access Grafana

```bash
kubectl get svc -n monitoring prometheus-stack-grafana \
  -o jsonpath='{.spec.ports.nodePort}'
kubectl port-forward -n monitoring \
  svc/prometheus-stack-grafana 3000:80 &
```

### Query Prometheus

```bash
kubectl port-forward -n monitoring \
  svc/prometheus-stack-kube-prom-prometheus 9090:9090 &
```

### Create a Custom Alert Rule

```bash
cat > /tmp/custom-alert.yaml << 'EOF'
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: lab-alerts
  namespace: monitoring
  labels:
    release: prometheus-stack
spec:
  groups:
  - name: lab-rules
    rules:
    - alert: PodCrashLooping
      expr: increase(kube_pod_container_status_restarts_total[15m]) > 3
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Pod {{ $labels.pod }} is crash looping"
        description: "Pod {{ $labels.pod }} in namespace {{ $labels.namespace }} has restarted more than 3 times in 15 minutes."
    - alert: NodeHighCPU
      expr: 100 - (avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 85
      for: 2m
      labels:
        severity: warning
      annotations:
        summary: "High CPU on {{ $labels.instance }}"
EOF

kubectl apply -f /tmp/custom-alert.yaml
kubectl get prometheusrule -n monitoring lab-alerts
```

### Deploy Loki Log Aggregation

```bash
kubectl get pods -n monitoring | grep loki
kubectl get pods -n monitoring | grep promtail
```

---

## 6. Falco — Runtime Security

### Check Falco Is Running

```bash
kubectl get pods -n falco
kubectl logs -n falco \
  $(kubectl get pods -n falco -o name | head -1) \
  --tail=20
```

### Trigger a Falco Alert

```bash
kubectl run trigger-test \
  --image=MASTER_IP:30001/airgap/alpine:3.20 \
  --rm -it --restart=Never \
  --privileged \
  -- sh -c "touch /pwned.txt && echo triggered"

kubectl logs -n falco \
  $(kubectl get pods -n falco -o name | head -1) \
  | grep "Write below root"
```

### Trigger "Shell in Container" Rule

```bash
kubectl run shell-test \
  --image=MASTER_IP:30001/airgap/alpine:3.20 \
  -- sleep 300

kubectl exec -it shell-test -- sh -c "id && ps"

kubectl logs -n falco \
  $(kubectl get pods -n falco -o name | head -1) \
  | grep "shell-test"

kubectl delete pod shell-test
```

### Write a Custom Falco Rule

```bash
cat > /tmp/custom-falco-rule.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: falco-custom-rules
  namespace: falco
data:
  custom_rules.yaml: |
    - rule: Sensitive File Read
      desc: Detect reading of sensitive files
      condition: >
        open_read and
        fd.name in (/etc/shadow, /etc/passwd, /etc/sudoers,
                    /root/.ssh/authorized_keys)
      output: >
        Sensitive file read (user=%user.name command=%proc.cmdline
        file=%fd.name container=%container.name)
      priority: WARNING
      tags: [filesystem, security]
EOF

kubectl apply -f /tmp/custom-falco-rule.yaml
kubectl logs -n falco \
  $(kubectl get pods -n falco -o name | head -1) \
  | grep "Sensitive file read"
```

---

## 7. Kyverno — Policy Enforcement

### Check Kyverno Is Running

```bash
kubectl get pods -n kyverno
kubectl get clusterpolicies
```

### Create a Policy — Require Resource Limits

```bash
cat > /tmp/require-limits.yaml << 'EOF'
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-resource-limits
spec:
  validationFailureAction: enforce
  rules:
  - name: check-resource-limits
    match:
      any:
      - resources:
          kinds:
          - Pod
    validate:
      message: "Resource limits are required for all containers."
      pattern:
        spec:
          containers:
          - name: "*"
            resources:
              limits:
                memory: "?*"
                cpu: "?*"
EOF

kubectl apply -f /tmp/require-limits.yaml
kubectl run no-limits \
  --image=MASTER_IP:30001/airgap/nginx:alpine
kubectl run with-limits \
  --image=MASTER_IP:30001/airgap/nginx:alpine \
  --limits='cpu=100m,memory=128Mi'
kubectl delete pod with-limits
kubectl delete clusterpolicy require-resource-limits
```

### Create a Policy — Disallow Privileged Containers

```bash
cat > /tmp/disallow-privileged.yaml << 'EOF'
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-privileged-containers
spec:
  validationFailureAction: enforce
  rules:
  - name: check-privileged
    match:
      any:
      - resources:
          kinds:
          - Pod
    validate:
      message: "Privileged containers are not allowed."
      pattern:
        spec:
          containers:
          - =(securityContext):
              =(privileged): "false"
EOF

kubectl apply -f /tmp/disallow-privileged.yaml
kubectl apply -f /tmp/priv-pod.yaml
kubectl delete clusterpolicy disallow-privileged-containers
```

### Generate Resources with Kyverno

```bash
cat > /tmp/generate-netpol.yaml << 'EOF'
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: default-deny-policy
spec:
  rules:
  - name: default-deny
    match:
      any:
      - resources:
          kinds:
          - Namespace
    generate:
      kind: NetworkPolicy
      name: default-deny-all
      namespace: "{{request.object.metadata.name}}"
      synchronize: true
      data:
        spec:
          podSelector: {}
          policyTypes:
          - Ingress
          - Egress
EOF

kubectl apply -f /tmp/generate-netpol.yaml
kubectl create namespace test-isolated
kubectl get networkpolicy -n test-isolated
kubectl delete namespace test-isolated
kubectl delete clusterpolicy default-deny-policy
```

---

## 8. Cert-Manager — TLS Automation

### Check Cert-Manager Is Running

```bash
kubectl get pods -n cert-manager
kubectl get crds | grep cert-manager
```

### Create a Self-Signed Certificate

```bash
cat > /tmp/self-signed-issuer.yaml << 'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
EOF

kubectl apply -f /tmp/self-signed-issuer.yaml

cat > /tmp/test-cert.yaml << 'EOF'
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: lab-cert
  namespace: default
spec:
  secretName: lab-cert-tls
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
  dnsNames:
  - lab.local
  - "*.lab.local"
  duration: 24h
  renewBefore: 1h
EOF

kubectl apply -f /tmp/test-cert.yaml
kubectl get certificate lab-cert -w
kubectl describe certificate lab-cert
kubectl get secret lab-cert-tls \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout

kubectl delete certificate lab-cert
kubectl delete clusterissuer selfsigned-issuer
kubectl delete secret lab-cert-tls
```

### Create a CA-Backed Issuer

```bash
cat > /tmp/ca-cert.yaml << 'EOF'
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: lab-ca
  namespace: cert-manager
spec:
  isCA: true
  secretName: lab-ca-secret
  subject:
    organizations:
    - Lab CA
  commonName: Lab Root CA
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
EOF

kubectl apply -f /tmp/ca-cert.yaml

cat > /tmp/ca-issuer.yaml << 'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: lab-ca-issuer
spec:
  ca:
    secretName: lab-ca-secret
EOF

kubectl apply -f /tmp/ca-issuer.yaml

cat > /tmp/app-cert.yaml << 'EOF'
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: app-cert
  namespace: default
spec:
  secretName: app-tls
  issuerRef:
    name: lab-ca-issuer
    kind: ClusterIssuer
  dnsNames:
  - myapp.lab.local
EOF

kubectl apply -f /tmp/app-cert.yaml
kubectl get certificate app-cert

kubectl delete certificate app-cert
kubectl delete clusterissuer lab-ca-issuer
kubectl delete certificate lab-ca -n cert-manager
kubectl delete secret lab-ca-secret -n cert-manager
kubectl delete secret app-tls
```

---

## 9. Terraform and OpenTofu — Infrastructure as Code

Both Terraform and OpenTofu are installed on `devops-1`. They are compatible, so the same configuration files work with either tool.

```bash
vagrant ssh devops-1
terraform --version
tofu --version
```

### Basic Terraform Workflow

```bash
mkdir -p ~/iac-lab && cd ~/iac-lab

cat > main.tf << 'EOF'
terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

resource "local_file" "hello" {
  filename = "/tmp/terraform-output.txt"
  content  = "Hello from Terraform ${terraform.workspace}!"
}

output "file_path" {
  value = local_file.hello.filename
}
EOF

terraform init
terraform plan
terraform apply -auto-approve
cat /tmp/terraform-output.txt

sed -i 's/Hello from/Updated by/' main.tf
terraform plan
terraform apply -auto-approve
cat /tmp/terraform-output.txt

terraform destroy -auto-approve
```

### Terraform State and Workspaces

```bash
terraform show
terraform state list

terraform workspace new dev
terraform workspace new staging
terraform workspace new prod

terraform workspace list
terraform workspace select dev
terraform apply -auto-approve

terraform workspace select staging
terraform apply -auto-approve

terraform workspace select default
terraform workspace delete dev
terraform workspace delete staging
terraform workspace delete prod
cd ~ && rm -rf ~/iac-lab
```

### OpenTofu Workflow

```bash
mkdir -p ~/opentofu-lab && cd ~/opentofu-lab

cat > main.tf << 'EOF'
terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

variable "environment" {
  default = "lab"
}

resource "local_file" "config" {
  filename = "/tmp/tofu-output.txt"
  content  = "OpenTofu environment: ${var.environment}"
}

output "environment" {
  value = var.environment
}
EOF

tofu init
tofu plan -var="environment=production"
tofu apply -var="environment=production" -auto-approve
cat /tmp/tofu-output.txt
tofu destroy -auto-approve

cd ~ && rm -rf ~/opentofu-lab
```

---

## 10. Kind Lab — Kubernetes in Docker

`kind-lab` runs a multi-node Kind cluster inside Docker.

```bash
vagrant ssh kind-lab
kind get clusters
kubectl get nodes
kubectl cluster-info
```

### Working with Kind

```bash
kubectl get nodes -o wide

kubectl create deployment hello \
  --image=nginx:alpine \
  --replicas=3

kubectl get pods -o wide
kubectl expose deployment hello \
  --type=NodePort --port=80
kubectl get svc hello

kubectl port-forward svc/hello 8888:80 &
curl http://localhost:8888

kubectl delete deployment hello
kubectl delete svc hello
```

### Create an Additional Kind Cluster

```bash
cat > /tmp/kind-cluster-2.yaml << 'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: cluster-2
nodes:
- role: control-plane
- role: worker
EOF

kind create cluster --config /tmp/kind-cluster-2.yaml
kind get clusters

kubectl config get-contexts
kubectl config use-context kind-cluster-2

kubectl get nodes

kubectl config use-context kind-lab
kind delete cluster --name cluster-2
```

### Load Local Images into Kind

```bash
cat > /tmp/Dockerfile.kind << 'EOF'
FROM nginx:alpine
RUN echo "Kind Lab Image" > /usr/share/nginx/html/index.html
EOF

docker build -t kind-app:1.0 -f /tmp/Dockerfile.kind /tmp
kind load docker-image kind-app:1.0 --name lab

kubectl run kind-app \
  --image=kind-app:1.0 \
  --image-pull-policy=Never

kubectl get pod kind-app
kubectl delete pod kind-app
```

---

## 11. K3d Lab — K3s in Docker

`k3d-lab` runs a K3s cluster inside Docker containers.

```bash
vagrant ssh k3d-lab
k3d cluster list
kubectl get nodes
```

### Working with K3d

```bash
kubectl get nodes -o wide

kubectl create deployment web \
  --image=nginx:alpine \
  --replicas=2

kubectl get pods -o wide
kubectl expose deployment web --type=NodePort --port=80

NODE_PORT=$(kubectl get svc web \
  -o jsonpath='{.spec.ports.nodePort}')
curl http://localhost:$NODE_PORT

kubectl delete deployment web
kubectl delete svc web
```

### Create Additional K3d Clusters

```bash
k3d cluster create dev-cluster \
  --servers 1 \
  --agents 2 \
  --port "9080:80@loadbalancer"

k3d cluster list

k3d kubeconfig merge dev-cluster --kubeconfig-merge-default

kubectl config get-contexts
kubectl config use-context k3d-dev-cluster

kubectl get nodes

kubectl config use-context k3d-k3s-default
k3d cluster delete dev-cluster
```

### K3d Registry Integration

```bash
k3d registry create lab-registry \
  --port 5000

docker pull nginx:alpine
docker tag nginx:alpine k3d-lab-registry:5000/nginx:alpine
docker push k3d-lab-registry:5000/nginx:alpine

kubectl run nginx-k3d \
  --image=k3d-lab-registry:5000/nginx:alpine

kubectl get pod nginx-k3d
kubectl delete pod nginx-k3d
k3d registry delete lab-registry
```

---

## 12. Linux Practice Nodes

Four Linux VMs are provided for operating system practice across different distributions.

```bash
vagrant ssh ubuntu-lab
vagrant ssh rocky-lab
vagrant ssh alma-lab
vagrant ssh suse-lab
```

### LVM Practice

```bash
vagrant ssh rocky-lab

lsblk
sudo pvcreate /dev/vdb /dev/vdc
sudo vgcreate lab-vg /dev/vdb /dev/vdc
sudo vgdisplay lab-vg

sudo lvcreate -L 2G -n data-lv lab-vg
sudo lvcreate -L 1G -n logs-lv lab-vg
sudo lvdisplay

sudo mkfs.xfs /dev/lab-vg/data-lv
sudo mkfs.xfs /dev/lab-vg/logs-lv

sudo mkdir -p /mnt/data /mnt/logs
sudo mount /dev/lab-vg/data-lv /mnt/data
sudo mount /dev/lab-vg/logs-lv /mnt/logs

df -h /mnt/data /mnt/logs

sudo lvextend -L +500M /dev/lab-vg/data-lv
sudo xfs_growfs /mnt/data
df -h /mnt/data
```

### Systemd Service Management

```bash
vagrant ssh ubuntu-lab

sudo tee /etc/systemd/system/lab-monitor.service << 'EOF'
[Unit]
Description=Lab Monitor
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash -c "while true; do echo \"[$(date)] Lab running\" >> /var/log/lab-monitor.log; sleep 60; done"
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable lab-monitor
sudo systemctl start lab-monitor
sudo systemctl status lab-monitor
sudo journalctl -u lab-monitor -f

sudo systemctl stop lab-monitor
sudo systemctl disable lab-monitor
sudo rm /etc/systemd/system/lab-monitor.service
sudo systemctl daemon-reload
```

### SELinux Practice

```bash
vagrant ssh rocky-lab

getenforce
sestatus
sudo ausearch -m avc -ts recent
ls -Z /etc/passwd
ls -Z /var/www/html 2>/dev/null || echo "path not found"

sudo setenforce 0
getenforce

sudo setenforce 1
getenforce

sudo mkdir /lab-web
sudo semanage fcontext -a -t httpd_sys_content_t "/lab-web(/.*)?"
sudo restorecon -Rv /lab-web
ls -Z /lab-web
```

### Firewall Practice

```bash
vagrant ssh ubuntu-lab

sudo ufw status
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw deny 23/tcp
sudo ufw enable
sudo ufw status numbered
sudo ufw delete 3
sudo ufw disable

vagrant ssh rocky-lab

sudo firewall-cmd --state
sudo firewall-cmd --get-active-zones
sudo firewall-cmd --list-all

sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --reload
sudo firewall-cmd --list-all
```

---

## 13. Ansible — Configuration Management

SSH keys are automatically distributed from `devops-1` to `node1` and `node2` during provisioning.

```bash
vagrant ssh devops-1

ansible all -i 'node1,node2,' -m ping

mkdir -p ~/inventory
cat > ~/inventory/hosts.ini << 'EOF'
[web]
node1

[db]
node2

[all:vars]
ansible_user=vagrant
EOF
```

### Ad-Hoc Commands

```bash
ansible all -i ~/inventory/hosts.ini -m command -a "uptime"
ansible all -i ~/inventory/hosts.ini -m command -a "df -h"
ansible all -i ~/inventory/hosts.ini -m command -a "free -m"

ansible all -i ~/inventory/hosts.ini \
  -m apt -a "name=htop state=present" \
  -b

echo "Lab config file" > /tmp/lab.conf
ansible all -i ~/inventory/hosts.ini \
  -m copy \
  -a "src=/tmp/lab.conf dest=/tmp/lab.conf mode=0644"

ansible all -i ~/inventory/hosts.ini \
  -m command -a "cat /tmp/lab.conf"
```

### Write a Playbook

```bash
mkdir -p ~/ansible-lab

cat > ~/ansible-lab/web-setup.yml << 'EOF'
***
- name: Configure web nodes
  hosts: web
  become: true
  vars:
    web_port: 80
    app_name: lab-app
  tasks:
    - name: Install nginx
      apt:
        name: nginx
        state: present
        update_cache: true

    - name: Create web root
      file:
        path: /var/www/{{ app_name }}
        state: directory
        mode: "0755"

    - name: Deploy index page
      copy:
        dest: /var/www/{{ app_name }}/index.html
        content: |
          <html>
          <body>
          <h1>{{ app_name }} - {{ inventory_hostname }}</h1>
          </body>
          </html>

    - name: Configure nginx virtualhost
      copy:
        dest: /etc/nginx/sites-available/{{ app_name }}
        content: |
          server {
            listen {{ web_port }};
            root /var/www/{{ app_name }};
            index index.html;
          }

    - name: Enable site
      file:
        src: /etc/nginx/sites-available/{{ app_name }}
        dest: /etc/nginx/sites-enabled/{{ app_name }}
        state: link

    - name: Start and enable nginx
      service:
        name: nginx
        state: started
        enabled: true

    - name: Verify nginx is running
      command: systemctl is-active nginx
      register: nginx_status
      changed_when: false

    - name: Show status
      debug:
        msg: "nginx is {{ nginx_status.stdout }}"
EOF

ansible-playbook ~/ansible-lab/web-setup.yml \
  -i ~/inventory/hosts.ini \
  --check

ansible-playbook ~/ansible-lab/web-setup.yml \
  -i ~/inventory/hosts.ini

curl http://node1/
```

### Ansible Roles

```bash
ansible-galaxy init ~/ansible-lab/roles/hardening
ls ~/ansible-lab/roles/hardening/

cat > ~/ansible-lab/roles/hardening/tasks/main.yml << 'EOF'
***
- name: Disable root SSH login
  lineinfile:
    path: /etc/ssh/sshd_config
    regexp: "^PermitRootLogin"
    line: "PermitRootLogin no"
  notify: Restart sshd

- name: Set password minimum length
  lineinfile:
    path: /etc/security/pwquality.conf
    regexp: "^minlen"
    line: "minlen = 14"
    create: true

- name: Set login failure lock
  lineinfile:
    path: /etc/security/faillock.conf
    regexp: "^deny"
    line: "deny = 5"
    create: true
EOF

cat > ~/ansible-lab/roles/hardening/handlers/main.yml << 'EOF'
***
- name: Restart sshd
  service:
    name: sshd
    state: restarted
EOF

cat > ~/ansible-lab/hardening-play.yml << 'EOF'
***
- name: Harden all nodes
  hosts: all
  become: true
  roles:
    - hardening
EOF

ansible-playbook ~/ansible-lab/hardening-play.yml \
  -i ~/inventory/hosts.ini --check
```

---

## 14. Day-2 Operations Tools

These tools are pre-installed on `devops-1`, `kind-lab`, and `k3d-lab`.

### k9s — Terminal UI for Kubernetes

```bash
vagrant ssh devops-1
k9s
```

### kubectx and kubens

```bash
kubectx
kubectx kind-lab
kubectx -

kubens
kubens monitoring

kubectl get pods
kubens default
```

### stern — Multi-Pod Log Streaming

```bash
vagrant ssh devops-1

stern -n argocd .
stern -n monitoring prometheus
stern -n argocd . --include="error|warn"
stern -n kyverno . --tail=10
stern -n falco . --timestamps
```

---

## 15. Lab Validation

Run the automated validation script to confirm all components are healthy:

```bash
cd labs/infrastructure/devops-linux-lab
./scripts/validate-lab.sh
```

The script checks host RAM, disk, and CPU; Vagrant and plugin versions; VM states; Kubernetes cluster health; node readiness; Harbor API health; Argo CD pod readiness; Prometheus and Grafana readiness; Falco and Kyverno pods; and network connectivity.

### Manual Health Checks

```bash
vagrant ssh devops-1

kubectl get nodes
kubectl get pods -A | grep -v Running | grep -v Completed

kubectl get pv
kubectl get pvc -A

kubectl get svc -A
kubectl get ingress -A

kubectl get events -A --sort-by='.lastTimestamp' | tail -20

kubectl get componentstatuses 2>/dev/null || true
```

---

## 16. Common Workflows

### Fast Iteration — Skip Enterprise Tooling

```bash
FAST_BOOT=true vagrant up devops-1 worker-1
```

### Export kubeconfig to Host Machine

```bash
export KUBECONFIG=/path/to/labs/infrastructure/devops-linux-lab/kubeconfig.yaml
kubectl get nodes
```

### Redeploy a Single Component

```bash
vagrant ssh devops-1

helm uninstall argocd -n argocd
kubectl delete namespace argocd

helm uninstall harbor -n harbor
kubectl delete namespace harbor
helm upgrade --install harbor harbor/harbor \
  -n harbor -f /opt/harbor-values.yaml \
  --wait --timeout 15m
```

### Lab Teardown

```bash
vagrant halt
vagrant destroy -f

rm -f .cluster_ready .k3s_token .cluster_state.json \
      kubeconfig.yaml ansible_key.pub lab.env
```

---

## 17. CI/CD Server

`cicd-server` hosts a self-contained DevSecOps pipeline: Gitea for source
control, Jenkins for automation, SonarQube for static analysis, Vault for
secrets, and OWASP ZAP for dynamic analysis, alongside Gitleaks and Trivy
CLI tools.

### First Boot

```bash
START_VMS=cicd-server vagrant up
# or, as part of:
LAB_PROFILE=full vagrant up
```

> Note: `devops-1`'s Ingress endpoint and Jenkins on `cicd-server` both
> default to host port 8080. Don't run both VMs at once until this is
> resolved, or edit `JENKINS_PORT` in the Vagrantfile.

### Get the Jenkins Admin Password

```bash
vagrant ssh cicd-server
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

### Run the Sample Pipeline

The sample pipeline lives at `/opt/jenkins/pipelines/DevSecOps-Pipeline.groovy`
and exercises: Gitea checkout → Gitleaks secret scan → Docker build → Trivy
image scan → Harbor push.

```bash
vagrant ssh cicd-server

# Inspect the sample app the pipeline builds
cat /opt/sample-app/app.py

# Run the scanning stages manually
gitleaks detect -r /opt/sample-app -v
docker build -t app:test /opt/sample-app
trivy image app:test --exit-code 0 --severity HIGH,CRITICAL
```

### Push to Harbor from the CI/CD VM

```bash
vagrant ssh cicd-server
harbor-push my-app 1.0
```

### Service URLs

See [Service Access](#service-access) above for Gitea, Jenkins, SonarQube,
Vault, and ZAP URLs and credentials.

---

## Disclaimer

This lab is for authorized learning and skill development only. Do not expose lab services on public networks. Treat all lab credentials as disposable and never reuse them on real systems.
