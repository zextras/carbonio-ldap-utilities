pipeline {
    agent {
        node {
            label 'carbonio-agent-v1'
        }
    }
    environment {
        JAVA_OPTS = '-Dfile.encoding=UTF8'
        LC_ALL = 'C.UTF-8'
        jenkins_build = 'true'
    }
    options {
        buildDiscarder(logRotator(numToKeepStr: '25'))
        timeout(time: 2, unit: 'HOURS')
        skipDefaultCheckout()
    }
    stages {
        stage('Checkout') {
            when {
                not {
                    buildingTag()
                }
            }
            steps {
                checkout scm
                dir('mailbox') {
                    checkout([$class: 'GitSCM',
                          branches: [[name: '*/main']],
                          userRemoteConfigs: [[credentialsId: 'tarsier_bot-ssh-key',
                                               name: 'mailbox',
                                               refspec: "refs/heads/main",
                                               url: 'git@github.com:zextras/carbonio-mailbox.git'
                                             ]]
                         ])
                }
                sh 'cp -r mailbox/store .'
                sh 'rm -rf mailbox'
            }
        }
        stage('Checkout on TAG') {
            when {
                buildingTag()
            }
            steps {
                checkout scm
                dir('mailbox') {
                    checkout([$class: 'GitSCM',
                          branches: [[name: '*/main']],
                          userRemoteConfigs: [[credentialsId: 'tarsier_bot-ssh-key',
                                               name: 'mailbox',
                                               refspec: "refs/heads/main",
                                               url: 'git@github.com:zextras/carbonio-mailbox.git'
                                             ]]
                         ])
                    sh 'git checkout $(git tag | tail -1)'
                }
                sh 'cp -r mailbox/store .'
                sh 'rm -rf mailbox'
            }
        }

        stage('Build') {
            steps {
                withCredentials([file(credentialsId: 'artifactory-jenkins-gradle-properties', variable: 'CREDENTIALS')]) {
                    sh '''
                        sudo apt update -y && sudo apt install -y ant-contrib
                        cat <<EOF > build.properties
                        debug=0
                        is-production=1
                        carbonio.buildinfo.version=22.3.0_ZEXTRAS_202203
                        EOF
                       '''
                    sh "cat ${CREDENTIALS} | sed -E 's#\\\\#\\\\\\\\#g' >> build.properties"
                    sh '''
                        ANT_RESPECT_JAVA_HOME=true JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64/ ant \
                             -propertyfile build.properties \
                             build-dist
                        '''
                }
            }
        }
        stage('Publish to maven') {
            when {
                buildingTag()
            }
            steps {
                withCredentials([file(credentialsId: 'artifactory-jenkins-gradle-properties', variable: 'CREDENTIALS')]) {
                    sh '''
                        sudo apt update -y && sudo apt install -y ant-contrib
                        cat <<EOF > build.properties
                        debug=0
                        is-production=1
                        carbonio.buildinfo.version=22.3.0_ZEXTRAS_202203
                        EOF
                       '''
                    sh "cat ${CREDENTIALS} | sed -E 's#\\\\#\\\\\\\\#g' >> build.properties"
                    sh '''
                        ANT_RESPECT_JAVA_HOME=true JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64/ ant \
                             -propertyfile build.properties \
                             build-dist
                        '''
                    sh '''
                        ANT_RESPECT_JAVA_HOME=true JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64/ ant \
                             -propertyfile build.properties \
                             publish-maven-all
                        '''
                    sh 'zip -r -9 ldap-ldif.zip build/dist'
                }
            }
            post {
                success {
                    archiveArtifacts artifacts: 'ldap-ldif.zip', fingerprint: true
                }
            }
        }
    }
}

