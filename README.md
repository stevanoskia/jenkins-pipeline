# jenkins-pipeline

A learning project that demonstrates a **CI/CD pipeline with Jenkins and GitHub**.
The app is a deliberately tiny Flask API; the focus is the delivery process:
pipeline-as-code, PR checks, branch protection, Docker images as releases,
staging → approval → prod, and automatic rollback.

## The app

| Endpoint | Returns |
|---|---|
| `GET /` | greeting + environment name |
| `GET /health` | `{"status": "ok"}` (used by the Docker health check and smoke tests) |
| `GET /version` | app version + git commit the image was built from |
| `GET /add?a=2&b=3` | `{"result": 5.0}` |
| `GET /multiply?a=2&b=3` | `{"result": 6.0}` |

## Run it locally

```bash
# lint + tests (same image Jenkins uses)
docker build --target test -t jenkins-pipeline-test .
docker run --rm jenkins-pipeline-test

# runtime image
docker build --target runtime -t jenkins-pipeline:dev .
docker run --rm -p 127.0.0.1:8000:8000 jenkins-pipeline:dev
curl http://127.0.0.1:8000/version
```

## Pipeline

Defined in [`Jenkinsfile`](Jenkinsfile), run by a Jenkins Multibranch Pipeline.

| Stage | Runs on | What it does |
|---|---|---|
| Prepare | all branches + PRs | computes the image tag `<version>-<build>-<short sha>` |
| Test | all branches + PRs | `docker build --target test`, runs ruff + pytest, publishes the JUnit report |
| Build image | all branches + PRs | `docker build --target runtime` |
| Push | `main` | logs in to Docker Hub with a token (isolated per-build docker config), pushes the image, records its **digest** |
| Deploy staging | `main` | [`scripts/deploy.ps1`](scripts/deploy.ps1): runs the image **by digest** as `jp-staging` on `127.0.0.1:8091`, waits for the container health check, smoke-tests `/health` + `/version` (must report the built commit), rolls back to the previous image on failure |

Branch and PR builds stop after "Build image" (their images are removed again); only `main` is released.
More stages (approval, prod) are added step by step.

### Triggers

Jenkins runs only on the local machine (127.0.0.1), so GitHub cannot call it directly. Webhooks are relayed:

```
GitHub webhook (push, pull_request) → smee.io channel → gosmee client (local) → Jenkins /github-webhook/
```

The webhook is signed with a shared secret (HMAC); Jenkins rejects events without a valid signature.
A periodic branch scan (every hour) is the fallback if the relay is down.

## Branching

Trunk-based: `main` is the only long-lived branch and the only one that deploys.
Changes go through short-lived branches and pull requests; Jenkins must report green before a PR can be merged.
