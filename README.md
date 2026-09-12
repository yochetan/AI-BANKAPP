# AI BankApp

A Spring Boot banking application with an integrated AI assistant (via Ollama), deployed to Kubernetes with a security-gated CI/CD pipeline.

## Tech Stack

- **Backend:** Java 21, Spring Boot (Maven)
- **Database:** MySQL
- **AI:** Ollama (local LLM inference)
- **Container Orchestration:** Kubernetes (kind for local/CI clusters)
- **CI/CD:** GitHub Actions

## Architecture

The app runs as a Deployment (`bankapp-deployment`) in the `bankapp` namespace, exposed via a NodePort Service on port `30080`. Two init containers block startup until MySQL (`3306`) and Ollama (`11434`) are reachable, so both must be deployed and healthy before the app comes up.

```
k8s/
├── bankapp-deployment.yml   # App deployment (waits on MySQL + Ollama)
├── service.yml              # Services: mysql, ollama, bankapp (NodePort 30080)
```

Health checks are exposed at `/actuator/health` and used for both readiness and liveness probes.

## Configuration

The app reads its config from:
- `bankapp-config-map` — non-secret environment variables
- `bankapp-secrets` — sensitive environment variables (DB credentials, etc.)

Both must exist in the `bankapp` namespace before deploying.

## CI/CD Pipeline

The pipeline runs as a series of gates, each blocking the next:

| Gate | Stage | Tool |
|------|-------|------|
| 1 | Secret scanning | Gitleaks |
| 2 | Lint | Checkstyle |
| 3 | SAST | Semgrep |
| 4 | SCA (dependency scan) | OWASP Dependency-Check |
| 8 | Deploy | kubectl → kind cluster |
| 9 | DAST | OWASP ZAP Baseline Scan |

Deployment targets a self-hosted runner with a running `bankapp-cluster` kind cluster and `kubectl` configured against it.

## Local Development

### Prerequisites
- Java 21 (Temurin)
- Maven
- Docker
- kind + kubectl

### Run the pipeline locally
1. Build and push the app image to your registry.
2. Ensure MySQL and Ollama are deployed and reachable in the `bankapp` namespace.
3. Apply manifests:
   ```bash
   kubectl apply -n bankapp -f k8s/service.yml
   kubectl apply -n bankapp -f k8s/bankapp-deployment.yml
   ```
4. Access the app at `http://localhost:30080`.

## Status / Known Gaps

- MySQL and Ollama Deployments are not yet included in this repo — only their Services are defined.
- ConfigMap and Secret manifests are not yet included; they must be provisioned separately.
- No build-and-push job exists yet to publish images to GHCR ahead of deployment.
