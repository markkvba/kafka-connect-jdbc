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
        
        // Kafka Connect service names per environment (configure in Jenkins)
        // KAFKA_CONNECT_SERVICE_DEV, KAFKA_CONNECT_SERVICE_STAGE, KAFKA_CONNECT_SERVICE_PROD
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build') {
            when {
                expression {
                    // Skip build if deploying AND a package archive already exists
                    if (params.DEPLOY_TO_KAFKA_CONNECT == true) {
                        def checkResult = sh(
                            script: 'test -d target/kafka-connect-jdbc-*-package',
                            returnStatus: true
                        )
                        if (checkResult == 0) {
                            echo "Deploy mode: Package archive found, skipping build"
                            return false
                        }
                    }
                    return true
                }
            }
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
                script {
                    // Get version from file written in Archive stage
                    def versionFile = readFile('/tmp/build_version.txt').trim()
                    def version = versionFile.replaceAll('VERSION=', '')
                    
                    // Determine host list and service name based on environment
                    def hosts = getDeploymentHosts(params.ENVIRONMENT)
                    def serviceName = getServiceName(params.ENVIRONMENT)
                    
                    if (!hosts || hosts.isEmpty()) {
                        error("No hosts configured for environment: ${params.ENVIRONMENT}")
                    }
                    
                    echo "Deploying kafka-connect-jdbc v${version} to ${params.ENVIRONMENT}"
                    echo "Target hosts: ${hosts.join(', ')}"
                    echo "Service name: ${serviceName}"
                    
                    def packageName = "kafka-connect-jdbc-${version}-package"
                    
                    // Deploy to each host
                    hosts.each { host ->
                        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                        echo "Deploying to: ${host}"
                        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                        
                        sh '''
                            # Create package tarball
                            cd ${WORKSPACE}/target
                            tar czf /tmp/${PACKAGE_NAME}.tar.gz ${PACKAGE_NAME}/
                            
                            # Copy package to remote host
                            scp -o StrictHostKeyChecking=no \
                                -o ConnectTimeout=10 \
                                -i ${SSH_KEY_FILE} \
                                /tmp/${PACKAGE_NAME}.tar.gz \
                                ${SSH_USER}@${HOST}:/tmp/
                            
                            # Copy deploy script to remote host
                            scp -o StrictHostKeyChecking=no \
                                -o ConnectTimeout=10 \
                                -i ${SSH_KEY_FILE} \
                                ${WORKSPACE}/scripts/deploy.sh \
                                ${SSH_USER}@${HOST}:/tmp/
                            
                            # Execute deployment script on remote host
                            ssh -o StrictHostKeyChecking=no \
                                -o ConnectTimeout=10 \
                                -i ${SSH_KEY_FILE} \
                                ${SSH_USER}@${HOST} \
                                "cd /tmp && tar xzf ${PACKAGE_NAME}.tar.gz && bash /tmp/deploy.sh /tmp/${PACKAGE_NAME} ${SERVICE_NAME}"
                        '''
                    }
                    
                    echo "✓ Deployment to all hosts complete"
                }
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

// Get list of Kafka Connect hosts for the specified environment from Jenkins credentials
def getDeploymentHosts(String environment) {
    def hostsVar = "KAFKA_CONNECT_HOSTS_${environment.toUpperCase()}"
    def hosts = env[hostsVar]
    
    if (!hosts) {
        echo "Warning: ${hostsVar} not configured in Jenkins environment"
        return []
    }
    
    // Parse space-separated host list
    return hosts.split('\\s+')
}

// Get Kafka Connect service name for the specified environment
def getServiceName(String environment) {
    def serviceVar = "KAFKA_CONNECT_SERVICE_${environment.toUpperCase()}"
    def serviceName = env[serviceVar]
    
    if (!serviceName) {
        echo "Error: ${serviceVar} not configured in Jenkins environment"
        return null
    }
    
    return serviceName
}
