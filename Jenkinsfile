// CI/CD pipeline for jenkins-pipeline.
// Runs on a Windows Jenkins controller that has Docker Desktop, so steps use `bat`
// (one docker command per step: each step fails on that command's exit code) and
// `powershell` for the deploy script.
//
// All branches + PRs: Prepare -> Test -> Build image                          (CI)
// main only:          Push -> Deploy staging -> Approve prod -> Deploy prod   (CD)
//
// No global agent: each phase takes an executor only while it works, so nothing is
// held while the build waits for the prod approval.

pipeline {
    agent none

    options {
        buildDiscarder(logRotator(numToKeepStr: '20'))
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
        stage('Build and staging') {
            agent any
            options { timeout(time: 30, unit: 'MINUTES') }
            stages {
                stage('Prepare') {
                    steps {
                        script {
                            env.APP_VERSION = readFile('VERSION').trim()
                            // kept in env: Deploy prod runs on a new agent allocation, after the approval
                            env.BUILD_SHA   = env.GIT_COMMIT
                            env.SHORT_SHA   = env.BUILD_SHA.take(7)
                            env.IMAGE_TAG   = "${env.APP_VERSION}-${env.BUILD_NUMBER}-${env.SHORT_SHA}"
                            // BUILD_TAG can contain characters Docker does not allow (e.g. %2F from branch names)
                            env.RUN_ID      = env.BUILD_TAG.toLowerCase().replaceAll('[^a-z0-9_.-]', '-')
                            env.TEST_IMAGE  = "jenkins-pipeline-test:${env.RUN_ID}"
                            // Own docker config per build: the Docker Hub login below never touches the
                            // user's Docker Desktop login, and it is deleted after the build.
                            env.DOCKER_CONFIG = "${env.WORKSPACE}\\.docker-ci"
                            currentBuild.description = "${env.IMAGE_NAME}:${env.IMAGE_TAG}"
                        }
                        // The isolated config still needs Docker Desktop's CLI plugins (buildx).
                        powershell '''
                            New-Item -ItemType Directory -Force $env:DOCKER_CONFIG | Out-Null
                            $cfg = @{ cliPluginsExtraDirs = @("$env:USERPROFILE\\.docker\\cli-plugins") } | ConvertTo-Json
                            [IO.File]::WriteAllText("$env:DOCKER_CONFIG\\config.json", $cfg)
                        '''
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
                        bat 'docker build --target runtime --build-arg APP_VERSION=%APP_VERSION% --build-arg GIT_SHA=%BUILD_SHA% -t %IMAGE_NAME%:%IMAGE_TAG% .'
                    }
                }

                stage('Push') {
                    when { branch 'main' }
                    steps {
                        withCredentials([usernamePassword(credentialsId: 'dockerhub',
                                                          usernameVariable: 'DH_USER',
                                                          passwordVariable: 'DH_TOKEN')]) {
                            // Single quotes: cmd expands the secret, Groovy never sees it. '@' stops cmd from
                            // echoing the expanded command line. Not `powershell`: Jenkins' PowerShell wrapper sets
                            // [Console]::InputEncoding to UTF-8 with BOM, so Windows PowerShell 5.1 would send
                            // EF BB BF in front of the token -> "unauthorized: incorrect username or password".
                            bat '@echo %DH_TOKEN%| docker login --username %DH_USER% --password-stdin'
                        }
                        bat 'docker push %IMAGE_NAME%:%IMAGE_TAG%'
                        script {
                            // The digest (sha256:...) identifies exactly these image bytes; tags can be moved, digests cannot.
                            env.IMAGE_REF = bat(returnStdout: true,
                                                script: '@docker inspect --format "{{index .RepoDigests 0}}" %IMAGE_NAME%:%IMAGE_TAG%').trim()
                            currentBuild.description = "${env.IMAGE_TAG} | ${env.IMAGE_REF}"
                        }
                        echo "Pushed ${env.IMAGE_REF}"
                    }
                }

                stage('Deploy staging') {
                    when { branch 'main' }
                    steps {
                        powershell '& ./scripts/deploy.ps1 -Environment staging -Port 8091 -Image $env:IMAGE_REF -ExpectedSha $env:BUILD_SHA; exit $LASTEXITCODE'
                    }
                }
            }
            post {
                always {
                    script {
                        // images from branch / PR builds are never deployed: remove them
                        if (env.BRANCH_NAME != 'main' && env.IMAGE_TAG) {
                            bat(returnStatus: true, script: 'docker image rm %IMAGE_NAME%:%IMAGE_TAG%')
                        }
                    }
                    // remove dangling layers left by rebuilds
                    bat(returnStatus: true, script: 'docker image prune -f')
                    // delete the per-build docker config (contains the Docker Hub login after Push)
                    bat(returnStatus: true, script: 'if exist "%DOCKER_CONFIG%" rmdir /s /q "%DOCKER_CONFIG%"')
                }
            }
        }

        stage('Approve prod') {
            when { branch 'main' }
            // No agent: waiting costs no executor. Reject or timeout -> build aborted, prod unchanged.
            options { timeout(time: 15, unit: 'MINUTES') }
            steps {
                script {
                    def approver = input(message: "Deploy ${env.IMAGE_TAG} to prod? (check staging first: http://127.0.0.1:8091/version)",
                                         ok: 'Deploy to prod',
                                         submitterParameter: 'APPROVER')
                    echo "Approved by ${approver}"
                }
            }
        }

        stage('Deploy prod') {
            when {
                beforeAgent true
                branch 'main'
            }
            agent any
            options { timeout(time: 10, unit: 'MINUTES') }
            steps {
                // Build once, deploy many: the same digest that was just verified in staging.
                bat 'docker pull %IMAGE_REF%'
                powershell '& ./scripts/deploy.ps1 -Environment prod -Port 8092 -Image $env:IMAGE_REF -ExpectedSha $env:BUILD_SHA; exit $LASTEXITCODE'
            }
        }
    }
}
