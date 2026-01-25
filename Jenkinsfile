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

    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Install & Build React') {
      steps {
        container('node') {
          sh '''
            cd web-tier
            npm install
            npm run build
          '''
        }
      }
    }

    stage('SonarQube Scan') {
      steps {
        container('sonar-scanner') {
          withSonarQubeEnv("${SONARQUBE}") {
            sh '''
              sonar-scanner \
              -Dsonar.projectKey=three-tier-frontend \
              -Dsonar.sources=web-tier/src
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

    stage('Build & Push Image') {
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

    stage('Trivy Scan') {
      steps {
        container('trivy') {
          sh '''
            trivy image --severity CRITICAL --exit-code 1 \
            $ECR_REGISTRY/$IMAGE_NAME:$IMAGE_TAG
          '''
        }
      }
    }

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
            git commit -m "Frontend image updated to $IMAGE_TAG"
            git push origin main
          '''
        }
      }
    }
  }

  success {
    echo "✅ Frontend CI passed — ArgoCD will deploy"
  }
}
