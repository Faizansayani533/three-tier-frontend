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

    // ---------------------------
    // BUILD & PUSH IMAGE
    // ---------------------------
    stage('Build & Push Image (Kaniko)') {
      steps {
        container('kaniko') {
          sh '''
            /kaniko/executor \
              --context . \
              --dockerfile Dockerfile \
              --destination $ECR_REGISTRY/$IMAGE_NAME:$IMAGE_TAG \
              --destination $ECR_REGISTRY/$IMAGE_NAME:latest
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
  }

stage('OWASP ZAP DAST Scan') {
  steps {
    sh '''
      mkdir -p zap-report

      docker run --rm -t \
        -v $(pwd)/zap-report:/zap/wrk \
        zaproxy/zap-stable zap-baseline.py \
        -t http://a998a5c39b13c427ebf3a09def396192-1140351167.eu-north-1.elb.amazonaws.com \
        -r zap-report.html || true
    '''
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
    archiveArtifacts artifacts: 'zap-report/*', fingerprint: true
	}  
   }
}
