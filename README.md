# Planning Poker — Dev Environment

Local orchestration for all Planning Poker microservices.

## Documentation

| Doc | Description |
|---|---|
| [docs/TECHNICAL.md](docs/TECHNICAL.md) | **Start here** — index, mental model, auth tiers |
| [docs/architecture/](docs/architecture/) | Service boundaries, auth/RBAC, Redis/Postgres |
| [docs/contracts/](docs/contracts/) | HTTP API, scope board, jira-service, WS/AI, sessions |
| [docs/development/GUIDE.md](docs/development/GUIDE.md) | Best practices, errors, testing, env vars |
| [docs/PRODUCT.md](docs/PRODUCT.md) | Product features for users |
| [infra/deploy/PRODUCTION.md](infra/deploy/PRODUCTION.md) | Production deploy runbook |

## Cursor workspace

Open the multi-root workspace (recommended):

```bash
cursor ~/Documents/GitHub/planning-poker-dev/planning-poker.code-workspace
```

Or in Cursor: **File → Open Workspace from File…** → `planning-poker.code-workspace`

Folders: `dev`, `voting-service`, `jira-service`, `web`.

Legacy monorepo `telegram_pb` is not part of this workspace.

## Clone all repos

```bash
./scripts/clone-all.sh
```

Expected layout (sibling directories):

```text
~/Documents/GitHub/
  planning-poker-dev/
  planning-poker-voting-service/
  planning-poker-jira-service/
  planning-poker-web/
```

## Quick start

```bash
cp .env.example .env
docker compose up -d postgres redis jira-service voting-service web
```

| Service | URL |
|---|---|
| Web | http://localhost:3001 |
| CMS | http://localhost:3001/cms |
| Jira service | http://localhost:8001/health |
| Voting service | http://localhost:8002/health |

## Tests

```bash
make backend-test    # pytest (voting-service)
make frontend-test   # vitest (web)
make check           # full CI-like check
```

## Deploy

Production: `https://planning.shults-sync.com` — see [PRODUCTION.md](infra/deploy/PRODUCTION.md).
