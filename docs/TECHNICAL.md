# Planning Poker — техническая документация

Документ для разработчиков: границы сервисов, контракты, потоки данных, ограничения и практики.

## С чего начать

1. Откройте [architecture/SERVICES.md](./architecture/SERVICES.md) — кто за что отвечает и что **запрещено** делать в каждом repo.
2. Прочитайте [architecture/AUTH.md](./architecture/AUTH.md) — три уровня auth и RBAC.
3. Нужен конкретный endpoint → [contracts/API.md](./contracts/API.md).
4. Scope board → [contracts/SCOPE-BOARD.md](./contracts/SCOPE-BOARD.md).
5. WebSocket / AI jobs → [contracts/REALTIME-AI.md](./contracts/REALTIME-AI.md).
6. Redis / Postgres → [architecture/DATA.md](./architecture/DATA.md).
7. Куда писать код, тесты, типичные ошибки → [development/GUIDE.md](./development/GUIDE.md).
8. Live sessions / voting → [contracts/SESSIONS.md](./contracts/SESSIONS.md).

Продуктовые сценарии: [PRODUCT.md](./PRODUCT.md).  
Деплой: [../infra/deploy/PRODUCTION.md](../infra/deploy/PRODUCTION.md).

---

## Мental model за 2 минуты

```text
Browser (React SPA, planning-poker-web)
    │  credentials: include (CMS cookie)
    │  /s/{token}, /r/{token} — без cookie, только token
    ▼
Caddy (HTTPS, VPN allowlist, WebSocket proxy)
    │
    ├── /              → web (nginx, static build)
    ├── /api/v1/*      → voting-service :8002
    └── /api/v1/ws/*   → voting-service :8002

voting-service
    ├── Postgres     cms_* read model, RBAC, scope boards, retros, sprint plans, standups
    ├── Redis        live sessions, web tokens, pub/sub, AI jobs, rate limits
    ├── jira-service :8001   (единственный путь к Jira REST)
    ├── Anthropic    task / scope / retro AI
    └── Telegram     session finish alerts

jira-service
    ├── Jira Cloud REST
    └── GitLab (optional) — evidence для role contributors
```

**Главное правило:** `voting-service` **никогда** не ходит в Jira напрямую. Только через `JIRA_SERVICE_URL`.

**Главное правило для UI:** бизнес-логика живёт в `voting-service/app/domain/`, не во frontend.

---

## Репозитории

| Repo | Порт (local) | Что внутри |
|---|---|---|
| `planning-poker-web` | 3001 / 5173 | React/Vite SPA |
| `planning-poker-voting-service` | 8002 | Sessions, CMS, scope, retro, AI |
| `planning-poker-jira-service` | 8001 | Stateless Jira adapter |
| `planning_poker_common` | — | Vendored in jira + voting (`vendor/planning-poker-common/`) |
| `planning-poker-dev` | — | Compose, Caddy, deploy, CI |

Legacy `telegram_pb` — не используется в prod.

Cursor workspace: `planning-poker.code-workspace` → папки `dev`, `voting-service`, `jira-service`, `web`.

---

## Три уровня авторизации

| Tier | Carrier | Endpoints | Проверка |
|---|---|---|---|
| **Public** | none или Redis token | `/web/*`, `/retro/join`, `/retro/card`, `/retro/vote`, `WS /ws/*`, `WS /retro-ws/*` | `web:{token}` / `web_retro:{token}` в Redis |
| **CMS cookie** | httpOnly `cms_token` (+ optional `Authorization: Bearer`) | `/cms/*` | Redis `cms_token:{token}` → Postgres principal |
| **Manager** | тот же CMS cookie + permission | `/app/*` | `require_permission(app.sessions.manage)` + team scope |

Подробнее: [architecture/AUTH.md](./architecture/AUTH.md).

---

## OpenAPI (dev)

| Service | URL |
|---|---|
| voting-service | http://localhost:8002/docs |
| jira-service | http://localhost:8001/docs |

Canonical types — в Pydantic-моделях и TypeScript `cmsClient.ts`, не только в Swagger.

---

## Локальный запуск

```bash
# из planning-poker-dev
cp .env.example .env
docker compose up -d postgres redis jira-service voting-service web
```

| URL | Назначение |
|---|---|
| http://localhost:3001/cms | CMS |
| http://localhost:8002/health | voting health |
| http://localhost:8001/health/ready | jira readiness |

```bash
make check   # voting + jira pytest, compileall, web test/build, compose validate
```

---

## Карта документации

| Документ | Содержание |
|---|---|
| [architecture/SERVICES.md](./architecture/SERVICES.md) | Границы сервисов, inter-service calls, health |
| [architecture/AUTH.md](./architecture/AUTH.md) | Cookie auth, RBAC, team scope |
| [architecture/DATA.md](./architecture/DATA.md) | Redis keys/TTL, Postgres schema, concurrency |
| [contracts/API.md](./contracts/API.md) | Все HTTP endpoints по роутерам |
| [contracts/SCOPE-BOARD.md](./contracts/SCOPE-BOARD.md) | Snapshot, refresh pipeline, metrics, AI |
| [contracts/JIRA-SERVICE.md](./contracts/JIRA-SERVICE.md) | Jira adapter contracts |
| [contracts/REALTIME-AI.md](./contracts/REALTIME-AI.md) | WebSocket, AI jobs, polling |
| [contracts/SESSIONS.md](./contracts/SESSIONS.md) | Sessions, voting flow, Jira import |
| [development/GUIDE.md](./development/GUIDE.md) | Best practices, errors, testing, env vars |
| [architecture/PYTHON-LIB.md](./architecture/PYTHON-LIB.md) | Shared `planning_poker_common` delivery |

---

## Быстрый справочник: куда смотреть в коде

| Задача | Файл |
|---|---|
| Router wiring | `voting-service/services/voting_service/main.py` |
| CMS API | `voting-service/services/voting_service/cms_api.py` |
| Manager cockpit API | `voting-service/services/voting_service/app_api.py` |
| Public voting + WS | `voting-service/services/voting_service/web_api.py` |
| Retro API | `voting-service/services/voting_service/retro_api.py` |
| Standups API | `voting-service/services/voting_service/cms/standups.py` |
| Auth / shared models | `voting-service/services/voting_service/_http_shared.py` |
| RBAC | `voting-service/services/voting_service/cms_rbac.py` |
| Team scope | `voting-service/services/voting_service/cms_team_access.py` |
| Scope domain | `voting-service/app/domain/scope_board.py` |
| AI jobs | `voting-service/services/voting_service/ai_jobs.py` |
| Jira routes | `jira-service/services/jira_service/api.py` |
| Frontend CMS client | `web/src/features/cms/api/cmsClient.ts` |
| HTTP + ApiError | `web/src/shared/api/http.ts` |
| AI poll | `web/src/shared/lib/pollAiJob.ts` |
