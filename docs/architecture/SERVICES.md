# Архитектура сервисов

## voting-service

**Repo:** `planning-poker-voting-service`  
**Порт:** 8002  
**Entrypoint:** `services/voting_service/main.py`

### Владеет (owns)

| Домен | Хранилище | Модули |
|---|---|---|
| Live planning poker sessions | Redis (`session:{chat_id}:{topic_id}`) + Postgres mirror (`cms_sessions`) | `redis_repository.py`, `app_api.py`, `web_api.py` |
| Web invite tokens | Redis `web:{token}` (TTL 8h) | `web_api.py` |
| CMS / admin | Postgres `cms_*` | `cms_api.py`, `cms_store.py` |
| RBAC | Postgres | `cms_rbac.py`, `cms_team_access.py` |
| Sprint plans | Postgres `cms_sprint_plans` | `cms_api.py` |
| Scope boards | Postgres `cms_scope_boards` + domain logic | `scope_board.py`, `cms_api.py` |
| Retrospectives | Redis live + Postgres durable | `retro_api.py`, `retro_redis_repository.py` |
| AI orchestration | Redis `ai_job:*` | `ai_jobs.py`, `ai_job_runners.py`, `*_llm.py` |
| Rate limits | Redis `rl:*`, `cms_login_fail:*` | `rate_limit.py` |
| Session finish Telegram | outbound HTTP | `session_finish_notify.py` |

### Не делает (must NOT)

- **Не вызывает Jira REST напрямую.** Только `JIRA_SERVICE_URL` → jira-service.
- **Не парсит changelog / role inference** — это jira-service.
- **Не отдаёт static UI** — это web + Caddy.

### Исходящие вызовы

```
voting-service ──HTTP──► jira-service:8001
    POST /api/v1/parse              — import задач в сессию
    POST /api/v1/search/scope       — refresh scope board
    GET  /api/v1/issue/{key}/context — AI context
    PUT  /api/v1/issue/{key}/story-points[ /fields]
    POST /api/v1/issue/{key}/comment/adf — AI export
    PUT  /api/v1/issue/{key}/comment/{id}/adf

voting-service ──HTTP──► api.anthropic.com/v1/messages
voting-service ──HTTP──► api.telegram.org (session finish)
```

HTTP session — singleton `app.state.http_session` (aiohttp pool). **Не создавать ClientSession на каждый request.**

### Роутеры (prefix `/api/v1`)

| Router | Tag | Auth |
|---|---|---|
| `app_router` | manager cockpit | CMS cookie + `app.sessions.manage` |
| `cms_router` | admin console | CMS cookie + RBAC per endpoint |
| `web_router` | participant voting | public token |
| `retro_router` | retro public + CMS | token / CMS cookie |

### Health

| Path | Ответ |
|---|---|
| `GET /health/` | `{status: "healthy", service: "voting-service", version: "1.0.0"}` |
| `GET /health/ready` | `{status: "ready"}` (200) или `{status: "not_ready", error}` (**503**) — **PING** на `app.state.web_redis`, **SELECT 1** на `repository`/`cms_store` pools; не создаёт новые адаптеры |
| `GET /health/live` | `{status: "alive"}` |
| `GET /metrics/` | Postgres CMS counters: `sessions_count`, `active_sessions`, `total_votes`, `postgres_ready` |

### Ограничения

- Без `POSTGRES_DSN` CMS недоступен (503 на `/cms/*`).
- Без `ANTHROPIC_API_KEY` AI endpoints возвращают ошибку.
- Optimistic concurrency на session mutations → **409** при конфликте (retry на клиенте).
- Scope refresh при partial Jira failure **не перезаписывает** snapshot (503, старый snapshot сохранён).

---

## jira-service

**Repo:** `planning-poker-jira-service`  
**Порт:** 8001  
**Entrypoint:** `services/jira_service/main.py`

### Владеет

- Все вызовы Jira Cloud REST.
- Enrichment scope issues: changelog, status milestones, role contributors.
- Optional GitLab evidence (`gitlab_http.py`, `gitlab_role_evidence.py`).
- In-memory issue cache (singleton `JiraServiceClient` в lifespan).

### Не делает

- Нет Postgres, Redis, sessions, RBAC, scope boards.
- **Не exposed наружу** — в prod Caddy проксирует только web + voting-service.

### Health

`GET /health/ready`:

```json
{
  "status": "ready",
  "jira_configured": true,
  "demo_fallback_enabled": false,
  "story_points_field": "customfield_10022"
}
```

HTTP 503 если Jira не сконфигурирован. Readiness проверяет singleton `app.state.jira_client` (`is_ready()`), **без** `JiraServiceClient()`/`close()` на каждый probe.

`GET /metrics/` — in-process cache: `cache_size`, `cache_hits`, `cache_misses`, `inflight_requests`, `ready`.

### Ограничения

- **Singleton client обязателен** — per-request client ломает cache.
- Rate limit на стороне jira-service **нет** — лимиты в voting-service + квоты Atlassian.
- `JIRA_DEMO_FALLBACK=true` — возвращает demo issues при misconfig (только dev).

Контракты endpoints: [../contracts/JIRA-SERVICE.md](../contracts/JIRA-SERVICE.md).

---

## web (React SPA)

**Repo:** `planning-poker-web`  
**Build:** Vite → nginx в Docker

### Владеет

- UI: `/cms`, `/manage`, `/s/:token`, `/r/:token`, `/demo`.
- Typed API client: `src/features/cms/api/cmsClient.ts`.
- Routing, loading/error states, WebSocket clients.

### Не делает

- Бизнес-логика scope metrics, RBAC checks, Jira enrichment — **только backend**.
- Хранение секретов — cookie httpOnly, не localStorage.
- Исключение: `pp_manager_session` хранит только `chatId` / `topicId` / `title` / `teamId` для возобновления cockpit после refresh. Invite token **не** пишется в storage — mint через `POST /app/sessions/{chat_id}/invite` или передаётся in-memory через router state после create/reopen.

### API base

`src/app/config.ts`:

```ts
cmsUrl(path)  → `${VITE_API_BASE}/api/v1/cms${path}`
appUrl(path)  → `${VITE_API_BASE}/api/v1/app${path}`
webUrl(path)  → `${VITE_API_BASE}/api/v1/web${path}`
```

Все CMS-запросы: `credentials: "include"`.

---

## planning-poker-dev

Compose, Caddy, deploy scripts, Grafana, k8s manifests (reference), CI notify workflows.

**Не содержит application code.**

---

## Prod topology

```text
Cloudflare (WebSockets ON, Full strict)
    ↓
Caddy (SITE_ALLOWED_IPS, trusted_proxies = Cloudflare CIDRs)
    ├── /           → web
    ├── /api/v1/*   → voting-service
    └── /api/v1/ws/* → voting-service

voting-service → postgres, redis, jira-service (internal network)
jira-service   → Atlassian Cloud, GitLab
```

`/health/*` — без allowlist (uptime probes).
