# Planning Poker — Dev Environment

Local orchestration for all Planning Poker microservices.

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
