# Planning Poker — Dev Environment

Local orchestration for all Planning Poker microservices.

## Cursor workspace

Open the multi-root workspace (recommended):

```bash
cursor ~/Documents/GitHub/planning-poker-dev/planning-poker.code-workspace
```

Or in Cursor: **File → Open Workspace from File…** → `planning-poker.code-workspace`

Folders: `dev`, `voting-service`, `jira-service`, `web`.

Legacy monorepo `telegram_pb` is not part of this workspace.

## Layout

```text
~/projects/
  planning-poker-jira-service/
  planning-poker-voting-service/
  planning-poker-web/
  planning-poker-dev/
```

```bash
cp .env.example .env
docker compose up -d postgres redis jira-service voting-service web
```

- Web: http://localhost:3001
- Jira: http://localhost:8001/health
- Voting: http://localhost:8002/health
