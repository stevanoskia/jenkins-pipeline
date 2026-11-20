<#
.SYNOPSIS
    Deploys an image as container jp-<Environment>, verifies it and rolls back on failure.

.DESCRIPTION
    1. Remembers which image the running container uses (for rollback).
    2. Replaces the container with one from the new image (127.0.0.1:<Port> -> 8000).
    3. Waits until Docker reports the container "healthy" (HEALTHCHECK in the Dockerfile).
    4. Smoke test: /health must be ok, /version must report the expected git commit.
    5. On any failure: prints the container log, starts the previous image again and exits 1.

.EXAMPLE
    ./scripts/deploy.ps1 -Environment staging -Port 8091 -Image andrejstev/jenkins-pipeline@sha256:... -ExpectedSha <commit>
#>
param(
    [Parameter(Mandatory = $true)][ValidateSet('staging', 'prod')][string]$Environment,
    [Parameter(Mandatory = $true)][int]$Port,
    [Parameter(Mandatory = $true)][string]$Image,
    [string]$ExpectedSha = '',
    [int]$TimeoutSec = 60
)

$ErrorActionPreference = 'Continue'
$name = "jp-$Environment"

function Invoke-Docker {
    & docker @args
    if ($LASTEXITCODE -ne 0) { throw "docker $($args -join ' ') failed with exit code $LASTEXITCODE" }
}

function Start-App([string]$img) {
    $runArgs = @(
        'run', '-d', '--name', $name, '--restart', 'unless-stopped',
        '-p', "127.0.0.1:${Port}:8000",
        '-e', "APP_ENV=$Environment",
        '--label', "jenkins-pipeline.env=$Environment",
        $img
    )
    Invoke-Docker @runArgs | Out-Null
}

function Wait-Healthy {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $status = & docker inspect --format '{{.State.Health.Status}}' $name
        if ($status -eq 'healthy') { return $true }
        if ($status -eq 'unhealthy') { break }
        Start-Sleep -Seconds 2
    }
    Write-Host "Container $name did not become healthy (last status: $status)"
    return $false
}

function Test-Smoke {
    try {
        $health = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 5
        $version = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/version" -TimeoutSec 5
    } catch {
        Write-Host "Smoke test request failed: $_"
        return $false
    }
    Write-Host "Smoke test: health=$($health.status) version=$($version.version) git_sha=$($version.git_sha)"
    if ($health.status -ne 'ok') { return $false }
    if ($ExpectedSha -and $version.git_sha -ne $ExpectedSha) {
        Write-Host "Expected git_sha $ExpectedSha"
        return $false
    }
    return $true
}

# --- 1. what is running now? ----------------------------------------------------
$previous = ''
if (& docker ps -a --filter "name=^${name}$" --format '{{.Names}}') {
    $previous = & docker inspect --format '{{.Config.Image}}' $name
}
$previousText = if ($previous) { $previous } else { 'none' }
Write-Host "Deploying $Image to $Environment (port $Port). Currently running: $previousText"

# --- 2.-4. replace, wait, verify ------------------------------------------------
$ok = $false
try {
    & docker image inspect $Image *> $null
    if ($LASTEXITCODE -ne 0) { Invoke-Docker pull $Image }
    if ($previous) { Invoke-Docker rm -f $name | Out-Null }
    Start-App $Image
    $ok = (Wait-Healthy) -and (Test-Smoke)
} catch {
    Write-Host "Deployment error: $_"
}

if ($ok) {
    Write-Host "Deployed $Image to ${Environment}: http://127.0.0.1:$Port"
    exit 0
}

# --- 5. roll back ----------------------------------------------------------------
Write-Host "Deployment to $Environment FAILED. Last container log lines:"
& docker logs --tail 20 $name 2>&1 | ForEach-Object { "  $_" }
& docker rm -f $name *> $null
if ($previous) {
    Write-Host "Rolling back $Environment to $previous"
    try {
        Start-App $previous
        if (Wait-Healthy) { Write-Host "Rollback OK: $Environment runs $previous again" }
        else { Write-Host "Rollback FAILED: $Environment is down" }
    } catch {
        Write-Host "Rollback FAILED: $_"
    }
} else {
    Write-Host "No previous version to roll back to; $Environment is down"
}
exit 1
