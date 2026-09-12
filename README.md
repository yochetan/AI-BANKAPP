# AI BankApp

![DevSecOps Main Pipeline](https://github.com/yochetan/AI-BANKAPP/actions/workflows/devsecops-main.yml/badge.svg)

A Spring Boot banking application with an integrated AI assistant (via Ollama), deployed to Kubernetes with a security-gated CI/CD pipeline.

## Tech Stack

- **Backend:** Java 21, Spring Boot (Maven)
- **Database:** MySQL 8.0
- **AI:** Ollama running `tinyllama`
- **Container Orchestration:** Kubernetes (kind, locally and in CI)
- **Registry:** GitHub Container Registry (GHCR)
- **CI/CD:** GitHub Actions

## Architecture

The app runs in the `bankapp` namespace as three Deployments — `bankapp-deployment`, `mysql-deployment`, and `ollama-deployment` — fronted by a NodePort Service on `30080`. `bankapp-deployment`'s init containers block startup until MySQL (`3306`) and Ollama (`11434`) are reachable, so both must be healthy before the app pod goes ready.

```
k8s/
├── bankapp-deployment.yml    # App deployment (waits on MySQL + Ollama)
├── mysql-deployment.yml      # MySQL 8.0
├── ollama-deployment.yml     # Ollama, pulls tinyllama on startup
├── service.yml                # Services: mysql, ollama, bankapp (NodePort 30080)
├── configMap.yml              # Non-secret env vars
├── secrets.yml                # DB credentials
├── persistentVolume.yml       # hostPath PVs for mysql/ollama
└── pvc.yml                    # PVCs bound to the PVs above

setup-k8s/
└── kind-config.yml            # kind cluster def: 1 control-plane + 2 workers,
                                # maps NodePort 30080 -> host port 8080
```

Health checks are exposed at `/actuator/health` and used for both readiness and liveness probes on the app.

## Configuration

The app reads its config from:
- `bankapp-config-map` — non-secret environment variables (DB host/port, Ollama URL, etc.)
- `bankapp-secrets` — sensitive environment variables (DB credentials)

Both are namespaced to `bankapp` and applied before the app or MySQL come up.

## CI/CD Pipeline

The pipeline runs as a chain of reusable workflows, each gating the next:

| Gate | Stage | Tool |
|------|-------|------|
| 1 | Secret scanning | Gitleaks |
| 2 | Lint | Checkstyle |
| 3 | SAST | Semgrep |
| 4 | SCA (dependency scan) | OWASP Dependency-Check |
| 5 | Build | Maven |
| 6 | Container image scan | Trivy |
| 7 | Push image | GHCR |
| 8 | Deploy | kind + kubectl |
| 9 | DAST | OWASP ZAP Baseline Scan |

`devsecops-main.yml` chains `ci.yml` → `build.yml` → `cd.yml` on pushes to `main`, `devsecops`, and `k8s`. `cd.yml` spins up a fresh kind cluster per run (GitHub-hosted runners are ephemeral, so the whole deploy-and-scan sequence lives in a single job to share that cluster), applies ConfigMap/Secrets/PVs/PVCs, brings up MySQL and Ollama and waits for them to be ready, then deploys the app and runs the ZAP scan against it.

## Local Development

### Prerequisites
- Java 21 (Temurin)
- Maven
- Docker
- kind + kubectl

### Run locally
1. Create the kind cluster using the repo's config, so the NodePort mapping matches what the app expects:
   ```bash
   kind create cluster --config setup-k8s/kind-config.yml
   ```
2. Build and load the image:
   ```bash
   docker build -t stupidgenuis/ai-bankapp:k8s .
   kind load docker-image stupidgenuis/ai-bankapp:k8s --name ai-bankapp-cluster
   ```
3. Apply manifests in order (PVs before PVCs, since they're statically bound by label selector rather than dynamically provisioned):
   ```bash
   kubectl apply -n bankapp -f k8s/configMap.yml
   kubectl apply -n bankapp -f k8s/secrets.yml
   kubectl apply -f k8s/persistentVolume.yml
   kubectl apply -n bankapp -f k8s/pvc.yml
   kubectl apply -n bankapp -f k8s/service.yml
   kubectl apply -n bankapp -f k8s/mysql-deployment.yml
   kubectl apply -n bankapp -f k8s/ollama-deployment.yml
   kubectl apply -n bankapp -f k8s/bankapp-deployment.yml
   ```
4. Access the app at `http://localhost:8080` (mapped from NodePort `30080` per `setup-k8s/kind-config.yml`).

## Notes / Gotchas

- **MySQL health checks use `--protocol=tcp`.** `mysqladmin ping -h localhost` forces a Unix socket connection at a compiled-in default path, which doesn't always match where a given `mysql:8.0` patch actually places its socket. Probes are pinned to `-h 127.0.0.1 --protocol=tcp` to avoid that mismatch.
- **kind node image is left unpinned.** Pinning to a specific `kindest/node` image (especially a release candidate) can fall out of sync with the installed `kind` CLI's expected kubeadm config version and break cluster creation entirely. Letting `kind` pick its own default avoids that class of failure.
- **NodePort ≠ host port.** `setup-k8s/kind-config.yml` maps container port `30080` to host port `8080` — the app is reachable at `localhost:8080` locally and in CI, not `localhost:30080`.
