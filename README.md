# planning-poker-dev

Local orchestration, production deploy scripts, and **canonical documentation** for the Planning Poker microservices stack.

Production: `https://planning.shults-sync.com`

## Repositories

| Repo | Role |
|---|---|
| [planning-poker-dev](https://github.com/shulzpavel/planning-poker-dev) | Compose, Caddy, deploy, CI notify, docs (this repo) |
| [planning-poker-voting-service](https://github.com/shulzpavel/planning-poker-voting-service) | Sessions, CMS/RBAC, scope, retro, AI |
| [planning-poker-jira-service](https://github.com/shulzpavel/planning-poker-jira-service) | Stateless Jira adapter |
| [planning-poker-web](https://github.com/shulzpavel/planning-poker-web) | React/Vite SPA |
| `planning_poker_common` | vendored in jira + voting (`vendor/planning-poker-common/`) |

Legacy monorepo `telegram_pb` is **not** used in production.

## Documentation

| Doc | Description |
|---|---|
| [docs/TECHNICAL.md](docs/TECHNICAL.md) | **Start here** — mental model, auth tiers, repo map |
| [docs/architecture/SERVICES.md](docs/architecture/SERVICES.md) | Service boundaries and forbidden cross-calls |
| [docs/contracts/](docs/contracts/) | HTTP, scope board, Jira, WebSocket/AI, sessions |
| [docs/development/GUIDE.md](docs/development/GUIDE.md) | Best practices, errors, testing, list pagination |
| [docs/architecture/PYTHON-LIB.md](docs/architecture/PYTHON-LIB.md) | Shared lib vendored in backend services |
| [docs/PRODUCT.md](docs/PRODUCT.md) | Product features |
| [infra/deploy/PRODUCTION.md](infra/deploy/PRODUCTION.md) | Production deploy runbook |

## Cursor workspace

```bash
cursor planning-poker.code-workspace
```

Folders: `dev`, `voting-service`, `jira-service`, `web`.

## Clone all repos

Sibling layout under one parent directory:

```bash
./scripts/clone-all.sh
```

```text
~/Documents/GitHub/
  planning-poker-dev/
  planning-poker-voting-service/
  planning-poker-jira-service/
  planning-poker-web/
```

Domain sync between backend services: `./scripts/sync-vendor-common.sh` ([PYTHON-LIB.md](docs/architecture/PYTHON-LIB.md)). The old `planning-poker-python-lib` repo is **archived** on GitHub.

## Quick start

```bash
cp .env.example .env
docker compose up -d postgres redis jira-service voting-service web
```

| URL | Service |
|---|---|
| http://localhost:3001/cms | Web UI |
| http://localhost:8002/docs | voting-service OpenAPI |
| http://localhost:8001/docs | jira-service OpenAPI |
| http://localhost:8002/health/ready | voting readiness |

## Tests

```bash
make backend-test    # pytest in voting-service + jira-service
make frontend-test   # vitest in web
make check           # backend + frontend + compileall + compose validate
```

## Deploy

| Change | Script |
|---|---|
| Full stack (default for backend) | `./infra/deploy/deploy-prod.sh` |
| Single service | `./infra/deploy/deploy-service-prod.sh voting-service` |
| Web only | `./infra/deploy/deploy-web-prod.sh` |

Runbook: [infra/deploy/PRODUCTION.md](infra/deploy/PRODUCTION.md).

**Practices:** deploy scripts pull this repo on each run; maintenance banner uses Redis ref-count for parallel service deploys; after Dockerfile changes run `docker build` locally before push (CI also smoke-checks `import planning_poker_common` in backend images).
