// CI/CD pipeline for jenkins-pipeline.
// Runs on a Windows Jenkins controller that has Docker Desktop, so steps use `bat`
// (one docker command per step: each step fails on that command's exit code).
// Current stage set: CI only (test + build image). CD stages are added later via a PR.

pipeline {
    agent any

    options {
        buildDiscarder(logRotator(numToKeepStr: '20'))
        timeout(time: 30, unit: 'MINUTES')
        disableConcurrentBuilds()
        timestamps()
    }

    environment {
        IMAGE_NAME  = 'andrejstev/jenkins-pipeline'
        // Talk to the Docker Desktop engine directly. Without this the docker CLI reads the
        // user's context files (~/.docker/contexts), which Docker Desktop sometimes locks
        // ("being used by another process") and the build fails at random.
        DOCKER_HOST = 'npipe:////./pipe/dockerDesktopLinuxEngine'
    }

    stages {
        stage('Prepare') {
            steps {
                script {
                    env.APP_VERSION = readFile('VERSION').trim()
                    env.SHORT_SHA   = env.GIT_COMMIT.take(7)
                    env.IMAGE_TAG   = "${env.APP_VERSION}-${env.BUILD_NUMBER}-${env.SHORT_SHA}"
                    // BUILD_TAG can contain characters Docker does not allow (e.g. %2F from branch names)
                    env.RUN_ID      = env.BUILD_TAG.toLowerCase().replaceAll('[^a-z0-9_.-]', '-')
                    env.TEST_IMAGE  = "jenkins-pipeline-test:${env.RUN_ID}"
                    currentBuild.description = "${env.IMAGE_NAME}:${env.IMAGE_TAG}"
                }
                echo "Branch ${env.BRANCH_NAME}, commit ${env.SHORT_SHA}, image tag ${env.IMAGE_TAG}"
            }
        }

        stage('Test') {
            steps {
                bat 'docker build --target test -t %TEST_IMAGE% .'
                script {
                    // Run lint + tests; keep the exit code so the JUnit report is copied out even on failure.
                    def rc = bat(returnStatus: true, script: 'docker run --name %RUN_ID%-test %TEST_IMAGE%')
                    bat 'if exist reports rmdir /s /q reports'
                    bat(returnStatus: true, script: 'docker cp %RUN_ID%-test:/app/reports reports')
                    if (rc != 0) {
                        error("Lint or unit tests failed (exit code ${rc})")
                    }
                }
            }
            post {
                always {
                    junit allowEmptyResults: true, testResults: 'reports/junit.xml'
                    bat(returnStatus: true, script: 'docker rm -f %RUN_ID%-test')
                    bat(returnStatus: true, script: 'docker image rm %TEST_IMAGE%')
                }
            }
        }

        stage('Build image') {
            steps {
                bat 'docker build --target runtime --build-arg APP_VERSION=%APP_VERSION% --build-arg GIT_SHA=%GIT_COMMIT% -t %IMAGE_NAME%:%IMAGE_TAG% .'
            }
        }
    }

    post {
        always {
            // remove dangling layers left by rebuilds
            bat(returnStatus: true, script: 'docker image prune -f')
        }
    }
}
