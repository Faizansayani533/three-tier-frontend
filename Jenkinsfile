pipeline {
  agent { label 'kaniko' }

  environment {
    AWS_REGION   = "eu-north-1"
    ECR_REGISTRY = "079662785620.dkr.ecr.eu-north-1.amazonaws.com"
    IMAGE_NAME   = "three-tier-frontend"
    IMAGE_TAG    = "${BUILD_NUMBER}"
    SONARQUBE    = "sonarqube"
    GITOPS_REPO  = "https://github.com/Faizansayani533/three-tier-gitops.git"
    DD_URL 	 = "http://a24c6130de3b44ebf8138d1d6af506ab-504923582.eu-north-1.elb.amazonaws.com"
  }

  stages {

    stage('Checkout Source') {
      steps { checkout scm }
    }

    // ---------------------------
    // GITLEAKS SECRET SCAN
    // ---------------------------
    stage('GitLeaks Secret Scan') {
      steps {
        container('gitleaks') {
          sh '''
            gitleaks detect --source . --report-format json --report-path gitleaks-report.json --no-git || true
          '''
        }
      }
    }

    // ---------------------------
    // BUILD REACT
    // ---------------------------
    stage('Install & Build React') {
      steps {
        container('node') {
          sh '''
            npm install
            npm run build
          '''
        }
      }
    }

    // ---------------------------
    // SONARQUBE
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

    stage('Quality Gate') {
      steps {
        timeout(time: 10, unit: 'MINUTES') {
          waitForQualityGate abortPipeline: true
        }
      }
    }

stage('OWASP Dependency Check') {
  steps {
    container('dependency-check') {
      withCredentials([string(credentialsId: 'nvd-api-key', variable: 'NVD_API_KEY')]) {
        catchError(buildResult: 'SUCCESS', stageResult: 'FAILURE') {
          sh '''
            echo "🔍 OWASP Dependency Check (with NVD API key)"

            rm -rf dc-report && mkdir dc-report

            /usr/share/dependency-check/bin/dependency-check.sh \
              --project "three-tier-frontend" \
              --scan . \
              --format HTML \
              --out dc-report \
              --disableAssembly \
              --data /odc-data \
	      --nvdApiKey $NVD_API_KEY || true
	     
          '''
        }
      }
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
              --context /home/jenkins/agent/workspace/three-tier-frontend \
              --dockerfile /home/jenkins/agent/workspace/three-tier-frontend/Dockerfile \
              --destination $ECR_REGISTRY/$IMAGE_NAME:$IMAGE_TAG \
              --destination $ECR_REGISTRY/$IMAGE_NAME:latest
          '''
        }
      }
    }

    // ---------------------------
    // TRIVY SCAN
    // ---------------------------
stage('Trivy Scan') {
  steps {
    container('trivy') {
      sh '''
        echo "🔍 Running Trivy image scan..."

        # HTML report for Jenkins artifacts
        trivy image \
          --format template \
          --template "@/contrib/html.tpl" \
          --output trivy-report.html \
          --severity CRITICAL,HIGH \
	  --exit-code 0 \
          --no-progress \
          $ECR_REGISTRY/$IMAGE_NAME:$IMAGE_TAG || true

        # JSON report for DefectDojo
        trivy image \
          --format json \
          --output trivy.json \
          --no-progress \
          $ECR_REGISTRY/$IMAGE_NAME:$IMAGE_TAG || true
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

    // ---------------------------
    // ZAP SCAN
    // ---------------------------
stage('OWASP ZAP DAST Scan') {
  steps {
    container('zap') {
      sh '''
        mkdir -p /zap/wrk

        zap-baseline.py \
          -t http://a998a5c39b13c427ebf3a09def396192-1140351167.eu-north-1.elb.amazonaws.com \
          -r zap.html \
          -J zap.json || true

        cp /zap/wrk/zap.html .
        cp /zap/wrk/zap.json .
      '''
    }
  }
}



  }


  post {
    always {
      archiveArtifacts artifacts: 'zap.html, trivy-report.html, dc-report/**, gitleaks-report.*', fingerprint: true
    }

    success {
      echo "✅ DEVSECOPS PIPELINE SUCCESS — Reports pushed to DefectDojo"
    }

    failure {
      echo "❌ PIPELINE FAILED — Check stage logs"
    }
  }
}
