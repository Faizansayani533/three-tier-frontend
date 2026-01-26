pipeline {
  agent { label 'kaniko' }

  environment {
    AWS_REGION   = "eu-north-1"
    ECR_REGISTRY = "079662785620.dkr.ecr.eu-north-1.amazonaws.com"
    IMAGE_NAME   = "three-tier-frontend"
    IMAGE_TAG    = "${BUILD_NUMBER}"
    SONARQUBE    = "sonarqube"
    GITOPS_REPO  = "https://github.com/Faizansayani533/three-tier-gitops.git"
  }

  stages {

    stage('Checkout Source') {
      steps {
        checkout scm
      }
    }

    // ---------------------------
    // INSTALL & BUILD REACT
    // ---------------------------
    stage('Install & Build React') {
      steps {
        container('node') {
          sh '''
            node -v
            npm -v
            npm install
            npm run build
          '''
        }
      }
    }

    // ---------------------------
    // SONARQUBE SCAN
    // ---------------------------
    stage('SonarQube Scan') {
      steps {
        container('sonar-scanner') {
          withSonarQubeEnv("${SONARQUBE}") {
            sh '''
              sonar-scanner \
              -Dsonar.projectKey=three-tier-frontend \
              -Dsonar.projectName=three-tier-frontend \
              -Dsonar.sources=src
            '''
          }
        }
      }
    }

    // ---------------------------
    // QUALITY GATE
    // ---------------------------
    stage('Quality Gate') {
      steps {
        timeout(time: 10, unit: 'MINUTES') {
          waitForQualityGate abortPipeline: true
        }
      }
    }

stage('Prepare Dependency-Check DB') {
  steps {
    container('dependency-check') {
      withCredentials([string(credentialsId: 'nvd-api-key', variable: 'NVD_API_KEY')]) {
        sh '''
          echo "📥 Preparing Dependency-Check DB..."

          if [ ! -d "/odc-data/nvdcve" ]; then
            echo "First time DB download..."
            /usr/share/dependency-check/bin/dependency-check.sh \
              --updateonly \
              --data /odc-data \
              --nvdApiKey $NVD_API_KEY
          else
            echo "Using existing offline DB"
          fi
        '''
      }
    }
  }
}

stage('OWASP Dependency Check') {
  steps {
    container('dependency-check') {
      sh '''
        echo "🔍 OWASP Dependency Check (OFFLINE MODE)"

        rm -rf dc-report
        mkdir dc-report

        /usr/share/dependency-check/bin/dependency-check.sh \
          --project "three-tier-frontend" \
          --scan . \
          --format HTML \
          --out dc-report \
          --disableAssembly \
          --data /odc-data \
          --noupdate \
          --failOnCVSS 9
      '''
    }
  }
}


    // ---------------------------
    // BUILD & PUSH IMAGE
    // ---------------------------
stage('Build & Push Image (Kaniko)') {
  steps {
    container('kaniko') {
      sh '''
        echo "INSIDE KANIKO CONTAINER"
        ls /kaniko

        /kaniko/executor \
          --context /home/jenkins/agent/workspace/three-tier-frontend \
          --dockerfile /home/jenkins/agent/workspace/three-tier-frontend/Dockerfile \
          --destination $ECR_REGISTRY/$IMAGE_NAME:$IMAGE_TAG \
          --destination $ECR_REGISTRY/$IMAGE_NAME:latest \
          --verbosity=info
      '''
    }
  }
}

    // ---------------------------
    // TRIVY IMAGE SCAN
    // ---------------------------
    stage('Trivy Scan') {
      steps {
        container('trivy') {
          sh '''
            trivy image \
              --severity CRITICAL \
              --exit-code 1 \
              --no-progress \
              $ECR_REGISTRY/$IMAGE_NAME:$IMAGE_TAG
          '''
        }
      }
    }

    // ---------------------------
    // UPDATE GITOPS REPO
    // ---------------------------
    stage('Update GitOps Repo') {
      steps {
        withCredentials([string(credentialsId: 'gitops-token', variable: 'GIT_TOKEN')]) {
          sh '''
            rm -rf gitops
            git clone https://$GIT_TOKEN@github.com/Faizansayani533/three-tier-gitops.git gitops

            cd gitops/frontend

            sed -i "s|image: .*|image: $ECR_REGISTRY/$IMAGE_NAME:$IMAGE_TAG|g" deployment.yaml

            git config user.email "jenkins@devsecops.com"
            git config user.name "jenkins"

            git add deployment.yaml
            git commit -m "Update frontend image to $IMAGE_TAG"
            git push origin main
          '''
        }
      }
    }
stage('OWASP ZAP DAST Scan') {
  steps {
    container('zap') {
      sh '''
        echo "🚨 Running OWASP ZAP DAST Scan..."

        mkdir -p zap-report

        zap-baseline.py \
          -t http://a998a5c39b13c427ebf3a09def396192-1140351167.eu-north-1.elb.amazonaws.com \
          -r zap-report/zap.html || true

        echo "✅ ZAP scan completed. Report saved in zap-report/zap.html"
      '''
    }
  }
}

  }

  post {
    success {
      echo "✅ FRONTEND PIPELINE PASSED — Argo CD will deploy UI"
    }

    failure {
      echo "❌ FRONTEND PIPELINE FAILED"
    }
      always {
    archiveArtifacts artifacts: 'zap-report/**', fingerprint: true
    }
  }
}
