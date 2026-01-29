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
              --format XML \
              --out dc-report \
              --disableAssembly \
              --data /odc-data \
	      --nvdApiKey $NVD_API_KEY
	      --failOnCVSS 9
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



    // =========================================================
    // =============== DEFECTDOJO UPLOAD STAGES ================
    // =========================================================

stage('Upload Reports via Proxy to DefectDojo') {
  steps {
    container('node') {
      withCredentials([string(credentialsId: 'defectdojo-api-key', variable: 'DD_API_KEY')]) {
        sh '''
          set -e

          apk add --no-cache aws-cli curl

          BUCKET=devsecops-defectdojo-reports
          BASE_PATH=three-tier/$BUILD_NUMBER
          PROXY_URL=http://defectdojo-proxy.defectdojo.svc.cluster.local:5000/import

          echo "⬆ Uploading reports to S3..."

          aws s3 cp gitleaks-report.json s3://$BUCKET/$BASE_PATH/gitleaks.json
          aws s3 cp dc-report/dependency-check-report.xml s3://$BUCKET/$BASE_PATH/dc.xml
          aws s3 cp trivy.json s3://$BUCKET/$BASE_PATH/trivy.json
          aws s3 cp zap.json s3://$BUCKET/$BASE_PATH/zap.json

          echo "🔗 Generating presigned URLs..."

          GITLEAKS_URL=$(aws s3 presign s3://$BUCKET/$BASE_PATH/gitleaks.json --expires-in 3600)
          DC_URL=$(aws s3 presign s3://$BUCKET/$BASE_PATH/dc.xml --expires-in 3600)
          TRIVY_URL=$(aws s3 presign s3://$BUCKET/$BASE_PATH/trivy.json --expires-in 3600)
          ZAP_URL=$(aws s3 presign s3://$BUCKET/$BASE_PATH/zap.json --expires-in 3600)

          echo "📝 Creating JSON payloads..."

          cat <<EOF > gitleaks.json
{
  "scan_type": "Gitleaks Scan",
  "engagement": "1",
  "file_url": "$GITLEAKS_URL"
}
EOF

          cat <<EOF > dc.json
{
  "scan_type": "Dependency Check Scan",
  "engagement": "1",
  "file_url": "$DC_URL"
}
EOF

          cat <<EOF > trivy.json
{
  "scan_type": "Trivy Scan",
  "engagement": "1",
  "file_url": "$TRIVY_URL"
}
EOF

          cat <<EOF > zap.json
{
  "scan_type": "ZAP Scan",
  "engagement": "1",
  "file_url": "$ZAP_URL"
}
EOF

          echo "🚀 Sending jobs to proxy..."

          curl -s -X POST $PROXY_URL -H "Content-Type: application/json" --data-binary @gitleaks.json
          curl -s -X POST $PROXY_URL -H "Content-Type: application/json" --data-binary @dc.json
          curl -s -X POST $PROXY_URL -H "Content-Type: application/json" --data-binary @trivy.json
          curl -s -X POST $PROXY_URL -H "Content-Type: application/json" --data-binary @zap.json

          echo "✅ All reports successfully submitted to proxy"
        '''
      }
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
