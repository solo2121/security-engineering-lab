# shellcheck shell=bash
          set -euo pipefail
          export MASTER_IP="@@CFG_IP@@"
          export HARBOR_PASS=@@HARBOR_PASS_ESCAPED@@
          export FAST_BOOT="@@FAST_BOOT@@"

          GITEA_VERSION="@@GITEA_VERSION@@"
          JENKINS_VERSION="@@JENKINS_VERSION@@"
          SONARQUBE_VERSION="@@SONARQUBE_VERSION@@"
          VAULT_VERSION="@@VAULT_VERSION@@"
          ZAP_VERSION="@@ZAP_VERSION@@"
          GITLEAKS_VERSION="@@GITLEAKS_VERSION@@"
          TRIVY_VERSION="@@TRIVY_VERSION@@"

          GITEA_PORT="@@GITEA_PORT@@"
          JENKINS_PORT="@@JENKINS_PORT@@"
          SONARQUBE_PORT="@@SONARQUBE_PORT@@"
          VAULT_PORT="@@VAULT_PORT@@"
          ZAP_PORT="@@ZAP_PORT@@"
          HARBOR_PORT="30001"
          JENKINS_AGENT_PORT="@@JENKINS_AGENT_PORT@@"

          MARKER_FILE="/var/lib/cicd_installed"

          if [ -f "$MARKER_FILE" ] && [ "$FAST_BOOT" = "true" ]; then
            echo "CI/CD tools already installed, skipping (FAST_BOOT=true)"
            exit 0
          fi

          log() { echo "[$(date +%Y-%m-%d_%H:%M:%S)] $*"; }

          echo "=========================================="
          echo "INSTALLING CI/CD AND SECURITY TOOLS"
          echo "=========================================="

          log "Installing Docker Compose..."
          curl -fsSL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose || echo "WARNING: Docker Compose download failed"
          chmod +x /usr/local/bin/docker-compose || true

          # ============================================================
          # 1. GITEA - Source Repository
          # ============================================================
          log "Installing Gitea ${GITEA_VERSION}..."
          mkdir -p /opt/gitea
          cat > /opt/gitea/docker-compose.yaml <<GITEA_EOF
        version: "3"
        services:
          gitea:
            image: gitea/gitea:${GITEA_VERSION}
            container_name: gitea
            environment:
              - GITEA__database__DB_TYPE=postgres
              - GITEA__database__HOST=db:5432
              - GITEA__database__NAME=gitea
              - GITEA__database__USER=gitea
              - GITEA__database__PASSWD=gitea
              - GITEA__server__DOMAIN=localhost
              - GITEA__server__HTTP_PORT=${GITEA_PORT}
              - GITEA__server__ROOT_URL=http://localhost:${GITEA_PORT}/
            restart: always
            volumes:
              - ./data:/data
              - ./conf:/etc/gitea
            ports:
              - "${GITEA_PORT}:${GITEA_PORT}"
              - "2222:22"
            depends_on:
              - db
            networks:
              - cicd-net
          db:
            image: postgres:14
            restart: always
            environment:
              - POSTGRES_USER=gitea
              - POSTGRES_PASSWORD=gitea
              - POSTGRES_DB=gitea
            volumes:
              - ./postgres:/var/lib/postgresql/data
            networks:
              - cicd-net
        networks:
          cicd-net:
            driver: bridge
GITEA_EOF

          cd /opt/gitea
          /usr/local/bin/docker-compose up -d || echo "WARNING: Gitea failed to start"

          # ============================================================
          # 2. JENKINS - CI/CD Orchestrator
          # ============================================================
          log "Installing Jenkins ${JENKINS_VERSION}..."
          mkdir -p /opt/jenkins
          cat > /opt/jenkins/Dockerfile <<JENKINS_EOF
        FROM jenkins/jenkins:${JENKINS_VERSION}
        USER root
        RUN apt-get update && apt-get install -y curl git docker.io python3 python3-pip && \
            apt-get clean && rm -rf /var/lib/apt/lists/*
        RUN curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh
        RUN usermod -aG docker jenkins
        USER jenkins
JENKINS_EOF

          cd /opt/jenkins
          docker build --build-arg JENKINS_VERSION=${JENKINS_VERSION} -t jenkins-lab . || echo "WARNING: Jenkins build failed"
          docker rm -f jenkins 2>/dev/null || true
          docker run -d --name jenkins             -p ${JENKINS_PORT}:8080 -p ${JENKINS_AGENT_PORT}:50000             -v /var/run/docker.sock:/var/run/docker.sock             -v jenkins_home:/var/jenkins_home             -e JENKINS_OPTS="--httpPort=8080"             jenkins-lab || echo "WARNING: Jenkins run failed"

          # ============================================================
          # 3. SONARQUBE - SAST
          # ============================================================
          log "Installing SonarQube ${SONARQUBE_VERSION}..."
          docker rm -f sonarqube 2>/dev/null || true
          docker run -d --name sonarqube             -p ${SONARQUBE_PORT}:9000             -e SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true             sonarqube:${SONARQUBE_VERSION} || echo "WARNING: SonarQube run failed"

          # ============================================================
          # 4. HASHICORP VAULT - Secrets Management (Dev Mode)
          # ============================================================
          log "Installing HashiCorp Vault ${VAULT_VERSION}..."
          docker rm -f vault 2>/dev/null || true
          docker run -d --name vault             -p ${VAULT_PORT}:8200             -e VAULT_DEV_ROOT_TOKEN_ID=root             --cap-add=IPC_LOCK             vault:${VAULT_VERSION} || echo "WARNING: Vault run failed"

          # ============================================================
          # 5. OWASP ZAP - DAST
          # ============================================================
          log "Installing OWASP ZAP ${ZAP_VERSION}..."
          docker rm -f zap 2>/dev/null || true
          docker run -d --name zap             -p ${ZAP_PORT}:8090             -v /tmp:/zap/wrk             owasp/zap2docker-stable:${ZAP_VERSION}             zap-daemon.sh -port 8090 || echo "WARNING: ZAP run failed"

          # ============================================================
          # 6. GITLEAKS + TRIVY CLI Tools
          # ============================================================
          log "Installing Gitleaks ${GITLEAKS_VERSION} and Trivy ${TRIVY_VERSION}..."

          curl -sSLO "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" || echo "WARNING: Gitleaks download failed"
          tar -xzf "gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" || true
          mv gitleaks /usr/local/bin/ || true
          rm -f "gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" LICENSE README.md || true

          apt-get update -qq
          apt-get install -y wget
          wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | apt-key add - || true
          # shellcheck disable=SC2046
          echo deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -cs) main | tee /etc/apt/sources.list.d/trivy.list
          apt-get update -qq
          apt-get install -y trivy || echo "WARNING: Trivy install failed"

          # ============================================================
          # 7. SAMPLE JENKINS PIPELINE
          # ============================================================
          log "Creating sample Jenkins pipeline..."
          mkdir -p /opt/jenkins/pipelines
          cat > /opt/jenkins/pipelines/DevSecOps-Pipeline.groovy <<PIPELINE_EOF
        pipeline {
            agent any

            environment {
                HARBOR_URL = 'https://${MASTER_IP}:30001'
                HARBOR_PROJECT = 'airgap'
                SONAR_HOST_URL = 'http://localhost:${SONARQUBE_PORT}'
                VAULT_ADDR = 'http://localhost:${VAULT_PORT}'
                VAULT_TOKEN = 'root'
            }

            stages {
                stage('Checkout') {
                    steps {
                        git 'http://localhost:${GITEA_PORT}/user/repo.git'
                    }
                }

                stage('Secret Scanning - Gitleaks') {
                    steps {
                        sh 'gitleaks detect -r . -v || true'
                    }
                }

                stage('Build') {
                    steps {
                        sh 'docker build -t app:${BUILD_NUMBER} .'
                    }
                }

                stage('Container Scanning - Trivy') {
                    steps {
                        sh 'trivy image app:${BUILD_NUMBER} --exit-code 0 --severity HIGH,CRITICAL || true'
                    }
                }

                stage('Push to Harbor') {
                    steps {
                        sh '''
                            echo "${HARBOR_PASS}" | docker login ${MASTER_IP}:30001 -u admin --password-stdin
                            docker tag app:${BUILD_NUMBER} ${MASTER_IP}:30001/${HARBOR_PROJECT}/app:${BUILD_NUMBER}
                            docker push ${MASTER_IP}:30001/${HARBOR_PROJECT}/app:${BUILD_NUMBER}
                        '''
                    }
                }
            }

            post {
                always {
                    sh 'docker system prune -f'
                }
                success {
                    echo 'Pipeline executed successfully!'
                }
                failure {
                    echo 'Pipeline failed! Check logs for details.'
                }
            }
        }
PIPELINE_EOF

          # ============================================================
          # 8. CREATE SAMPLE APPLICATION
          # ============================================================
          log "Creating sample application..."
          mkdir -p /opt/sample-app
          cat > /opt/sample-app/Dockerfile <<'APP_EOF'
        FROM python:3.9-slim
        WORKDIR /app
        COPY app.py .
        RUN pip install flask
        EXPOSE 5000
        CMD ["python", "app.py"]
APP_EOF

          cat > /opt/sample-app/app.py <<'APP_EOF'
        from flask import Flask
        import os

        app = Flask(__name__)

        @app.route('/')
        def hello():
            return 'Hello from DevSecOps Pipeline!'

        @app.route('/health')
        def health():
            return {'status': 'healthy'}

        if __name__ == '__main__':
            app.run(host='0.0.0.0', port=5000)
APP_EOF

          cat > /opt/sample-app/requirements.txt <<'APP_EOF'
        flask==2.2.3
APP_EOF

          # ============================================================
          # 9. HARBOR PUSH SCRIPT
          # ============================================================
          log "Creating Harbor integration script..."
          cat > /usr/local/bin/harbor-push <<'HARBOR_EOF'
        #!/bin/bash
        if [ $# -lt 2 ]; then
            echo "Usage: harbor-push <image-name> <tag>"
            exit 1
        fi

        IMAGE_NAME="$1"
        TAG="$2"
        HARBOR_REGISTRY="${MASTER_IP}:30001"
        HARBOR_PROJECT="airgap"

        echo "Pushing ${IMAGE_NAME}:${TAG} to Harbor..."
        docker tag "${IMAGE_NAME}:${TAG}" "${HARBOR_REGISTRY}/${HARBOR_PROJECT}/${IMAGE_NAME}:${TAG}"
        docker push "${HARBOR_REGISTRY}/${HARBOR_PROJECT}/${IMAGE_NAME}:${TAG}"
        echo "Push complete!"
HARBOR_EOF
          chmod +x /usr/local/bin/harbor-push

          echo ""
          echo "=========================================="
          echo "CI/CD AND SECURITY TOOLS INSTALLED"
          echo "=========================================="
          echo ""
          echo "Services:"
          echo "  Gitea:      http://localhost:${GITEA_PORT}"
          echo "  Jenkins:    http://localhost:${JENKINS_PORT}"
          echo "  SonarQube:  http://localhost:${SONARQUBE_PORT} (admin/admin)"
          echo "  Vault:      http://localhost:${VAULT_PORT} (token: root)"
          echo "  ZAP:        http://localhost:${ZAP_PORT}"
          echo ""
          echo "CLI Tools:"
          echo "  gitleaks --version"
          echo "  trivy --version"
          echo ""
          echo "Sample Files:"
          echo "  Pipeline:     /opt/jenkins/pipelines/DevSecOps-Pipeline.groovy"
          echo "  Sample App:   /opt/sample-app/"
          echo "  Harbor Push:  /usr/local/bin/harbor-push"
          echo ""
          echo "Harbor Registry: https://${MASTER_IP}:30001"
          echo "  Username: admin"
          echo "  Password: ${HARBOR_PASS}"
          echo ""
          echo "=========================================="
          echo "Jenkins Initial Admin Password:"
          docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null || echo "Check Jenkins logs"
          echo ""
          echo "To get Jenkins password: docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword"
          echo "=========================================="

          touch "$MARKER_FILE"
