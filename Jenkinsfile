pipeline {
    agent any
    
    tools {
        jdk 'JDK11'
        maven 'Maven3'
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timestamps()
        disableConcurrentBuilds()
    }

    parameters {
        choice(
            name: 'ENVIRONMENT',
            choices: ['dev', 'sqa', 'stage', 'prod'],
            description: 'Target environment for deployment'
        )
        booleanParam(
            name: 'DEPLOY_TO_KAFKA_CONNECT',
            defaultValue: false,
            description: 'Enable remote deployment to Kafka Connect nodes (requires SSH key setup)'
        )
    }

    environment {
        // SSH deployment settings (shared with SMT)
        SSH_KEY_FILE = '~/.ssh/kafka_connect_key'            // SSH key path
        SSH_USER = 'ec2-user'                                // SSH user for remote hosts
        
        // Maven cache OUTSIDE workspace (persists across Jenkins workspace cleanups)
        // Uses global ~/.m2 so multiple Kafka builds share the same cache
        MAVEN_OPTS = "-Dmaven.repo.local=${HOME}/.m2"
        
        // Kafka Connect host lists per environment (space-separated)
        // Configure in Jenkins as environment variables:
        // KAFKA_CONNECT_HOSTS_DEV, KAFKA_CONNECT_HOSTS_STAGE, KAFKA_CONNECT_HOSTS_PROD
        
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build') {
            steps {
                sh 'mvn clean package -DskipTests -Dcheckstyle.skip=true -T 1C'
            }
        }

        stage('Archive') {
            steps {
                sh '''
                    VERSION=$(mvn help:evaluate -Dexpression=project.version -q -DforceStdout)
                    echo "VERSION=${VERSION}" > /tmp/build_version.txt
                    echo "Artifact version: ${VERSION}"
                    
                    # Verify package distribution was created
                    PACKAGE_DIR="target/kafka-connect-jdbc-${VERSION}-package"
                    if [ ! -d "${PACKAGE_DIR}" ]; then
                        echo "Error: Package distribution not found at ${PACKAGE_DIR}"
                        exit 1
                    fi
                    echo "Package directory: ${PACKAGE_DIR}"
                '''
                archiveArtifacts artifacts: "target/kafka-connect-jdbc-*-package/**",
                                 allowEmptyArchive: false
            }
        }

        stage('Deploy to Kafka Connect') {
            when {
                expression { params.DEPLOY_TO_KAFKA_CONNECT == true }
            }
            steps {
                sh '''
                    set -e
                    
                    # Get version from file written in Archive stage
                    VERSION=$(cat /tmp/build_version.txt | sed 's/VERSION=//')
                    
                    # Get hosts for environment
                    ENV_UPPER=$(echo ${ENVIRONMENT} | tr '[:lower:]' '[:upper:]')
                    HOSTS_VAR="KAFKA_CONNECT_HOSTS_${ENV_UPPER}"
                    
                    # Use bash indirect expansion
                    HOSTS="${!HOSTS_VAR}"
                    
                    if [ -z "$HOSTS" ]; then
                        echo "Error: $HOSTS_VAR not configured"
                        exit 1
                    fi
                    
                    PACKAGE_NAME="kafka-connect-jdbc-${VERSION}-package"
                    PACKAGE_PATH="${WORKSPACE}/target/${PACKAGE_NAME}"
                    
                    echo "Deploying kafka-connect-jdbc v${VERSION} to ${ENVIRONMENT}"
                    echo "Target hosts: ${HOSTS}"
                    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                    
                    # Deploy to each host
                    for HOST in $HOSTS; do
                        echo "Deploying to: $HOST"
                        
                        # Copy package directory to remote host
                        scp -r -o StrictHostKeyChecking=no \
                            -o ConnectTimeout=10 \
                            -i ${SSH_KEY_FILE} \
                            ${PACKAGE_PATH} \
                            ${SSH_USER}@${HOST}:/tmp/
                        
                        # Copy deploy script to remote host via temp, then move to final location
                        scp -o StrictHostKeyChecking=no \
                            -o ConnectTimeout=10 \
                            -i ${SSH_KEY_FILE} \
                            ${WORKSPACE}/scripts/deploy.sh \
                            ${SSH_USER}@${HOST}:/tmp/
                        
                        # Move deploy script to executable directory and execute
                        ssh -o StrictHostKeyChecking=no \
                            -o ConnectTimeout=10 \
                            -i ${SSH_KEY_FILE} \
                            ${SSH_USER}@${HOST} \
                            "sudo mv /tmp/deploy.sh /usr/local/bin/res_scripts/kafka-connect-jdbc-deploy.sh && sudo chown root:root /usr/local/bin/res_scripts/kafka-connect-jdbc-deploy.sh && sudo chmod 755 /usr/local/bin/res_scripts/kafka-connect-jdbc-deploy.sh && bash /usr/local/bin/res_scripts/kafka-connect-jdbc-deploy.sh /tmp/${PACKAGE_NAME} -c"
                    done
                    
                    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                    echo "✓ Deployment to all hosts complete"
                '''
            }
        }
    }

    post {
        always {
            cleanWs()
        }
        success {
            echo "✓ kafka-connect-jdbc built and deployed successfully to ${params.ENVIRONMENT}"
        }
        failure {
            echo "✗ Build or deployment failed"
        }
    }

}

