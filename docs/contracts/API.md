# HTTP API — обзор

Base URL (prod): `https://planning.shults-sync.com/api/v1`

Все ответы об ошибках — FastAPI shape:

```json
{ "detail": "string" }
```

или validation array для 422.

Frontend парсит через `ApiError` (`web/src/shared/api/http.ts`).

---

## health / metrics (public)

| Method | Path | Auth |
|---|---|---|
| GET | `/health/` | none |
| GET | `/health/ready` | none |
| GET | `/health/live` | none |
| GET | `/metrics/` | none |

---

## web_router — participant voting

**Auth:** public token (no CMS cookie)

| Method | Path | Body / params | Response |
|---|---|---|---|
| POST | `/web/token` | `{chat_id, topic_id?}` | `{token, url}` |
| POST | `/web/join` | `{token, email, role}` | `{participant_id, ...}` |
| GET | `/web/state/{token}` | — | `WebSessionState` |
| POST | `/web/vote` | `{token, participant_id, value, track?}` | `{ok}` |
| WS | `/ws/{token}` | — | see [REALTIME-AI.md](./REALTIME-AI.md) |

Rate limits: token mint 10/min IP, join 30/min IP, vote 30/min participant.

---

## app_router — manager cockpit

**Auth:** CMS cookie + `app.sessions.manage` + team scope

### Sessions

| Method | Path | Notes |
|---|---|---|
| POST | `/app/sessions` | `{title, team_id?, estimation_mode?}` |
| POST | `/app/demo-session` | gated by `ENABLE_DEMO_SESSION` |
| GET | `/app/sessions/{chat_id}/state` | full manager state |
| GET | `/app/sessions/{chat_id}/completed` | completed tasks |
| POST | `/app/sessions/{chat_id}/invite` | new web token |
| PATCH | `/app/sessions/{chat_id}/title` | rename |

### Tasks

| Method | Path | Body highlights |
|---|---|---|
| POST | `/app/sessions/{chat_id}/tasks` | `TaskCreateRequest`: summary, jira_key?, url?, story_points?, expected_version? |
| PATCH | `/app/sessions/{chat_id}/tasks/{id}` | `TaskUpdateRequest` |
| DELETE | `/app/sessions/{chat_id}/tasks/{id}` | |
| POST | `/app/sessions/{chat_id}/tasks/{id}/move` | bucket move |
| POST | `/app/sessions/{chat_id}/tasks/reorder` | |
| POST | `/app/sessions/{chat_id}/tasks/jira-preview` | `{jql}` → preview list |
| POST | `/app/sessions/{chat_id}/tasks/jira-import` | `{issue_keys[]}` |

Field constraints (`_http_shared.py`): `summary: 1..500`, `jira_key: <=64`, `story_points: 0..MAX`.

### Voting flow

| Method | Path |
|---|---|
| POST | `/app/sessions/{chat_id}/start` |
| POST | `/app/sessions/{chat_id}/next` |
| POST | `/app/sessions/{chat_id}/skip` |
| POST | `/app/sessions/{chat_id}/final-estimate` |
| POST | `/app/sessions/{chat_id}/finish` |
| POST | `/app/sessions/{chat_id}/completed/{task_id}/reopen` |

### AI summary (task)

| Method | Path | Query |
|---|---|---|
| POST | `/app/sessions/{chat_id}/ai-summary` | `async=1`, `refresh=1` |
| GET | `/app/sessions/{chat_id}/ai-summary/jobs/{job_id}` | poll |

### Reports / Jira writeback

| Method | Path | Notes |
|---|---|---|
| GET | `/app/sessions/{chat_id}/summary` | |
| GET | `/app/sessions/{chat_id}/summary.csv` | |
| GET | `/app/sessions/{chat_id}/summary.md` | |
| POST | `/app/sessions/{chat_id}/jira-story-points/sync` | team scope via `_require_manager_session` |

---

## cms_router — admin

**Auth:** CMS cookie + RBAC per endpoint

### Auth

| Method | Path | Permission |
|---|---|---|
| POST | `/cms/auth/login` | public (rate limited) |
| POST | `/cms/auth/logout` | AuthDep |
| GET | `/cms/auth/me` | AuthDep |
| PATCH | `/cms/auth/me/preferences` | AuthDep |

### Core

| Method | Path | Permission |
|---|---|---|
| GET | `/cms/overview` | `cms.overview.view` |
| GET/POST | `/cms/teams` | AuthDep / superuser write |
| PATCH | `/cms/teams/{id}` | superuser |

### Sessions (CMS view)

| Method | Path | Permission |
|---|---|---|
| GET | `/cms/sessions` | `cms.sessions.view` |
| GET | `/cms/sessions/{id}` | `cms.sessions.view` |
| PATCH | `/cms/sessions/{id}` | rename |
| POST | `/cms/sessions/{id}/close` | `app.sessions.manage` |
| DELETE | `/cms/sessions/{id}` | hard delete + team scope |
| DELETE | `/cms/tokens/{id}` | `app.sessions.manage` + team scope via parent session |
| CRUD | `/cms/sessions/{id}/tasks/*` | `cms.tasks.manage` |

### Access (RBAC admin)

| Method | Path | Permission |
|---|---|---|
| GET | `/cms/access/permissions` | `cms.access.view` |
| GET | `/cms/access/pages` | `cms.access.view` |
| GET/POST/PATCH | `/cms/access/roles[/{id}]` | view / manage |
| GET/POST/PATCH | `/cms/access/admins[/{id}]` | view / manage |

### Sprint plans

| Method | Path | Permission |
|---|---|---|
| GET/POST | `/cms/sprint-plans` | `cms.planner.view` |
| GET/PUT/DELETE | `/cms/sprint-plans/{id}` | `cms.planner.view` |

### Scope boards

| Method | Path | Permission |
|---|---|---|
| GET/POST | `/cms/scope-boards` | `cms.planner.view` |
| GET/PATCH/DELETE | `/cms/scope-boards/{id}` | `cms.planner.view` |
| PATCH | `/cms/scope-boards/{id}/layout` | layout DnD |
| PATCH | `/cms/scope-boards/{id}/flow-pace-chart-order` | donut chart DnD order (`chart_order: string[]`) |
| PATCH | `/cms/scope-boards/{id}/release-comments` | |
| POST | `/cms/scope-boards/{id}/refresh` | Jira → snapshot |
| POST | `/cms/scope-boards/{id}/analyze` | AI (sync or `?async=1`) |
| GET | `/cms/scope-boards/{id}/analyze/jobs/{job_id}` | poll |
| GET | `/cms/scope-boards/{id}/ai-summary/jira-export` | Jira export poll (light) |
| POST | `/cms/scope-boards/{id}/questions` | manual question |
| POST | `/cms/scope-boards/{id}/questions/{qid}/resolve` | |
| POST/DELETE | `/cms/scope-boards/{id}/top-items[/{id}]` | |
| POST/PATCH/DELETE | `/cms/scope-boards/{id}/todo-items[/{id}]` | |
| POST | `/cms/scope-boards/{id}/issues/{key}/comment` | ADF → Jira |
| PUT | `/cms/scope-boards/{id}/issues/{key}/report-comment` | local comment |
| POST | `/cms/scope-boards/{id}/queues/{kind}/reorder` | `kind: todo\|test` |
| POST | `/cms/scope-boards/{id}/queues/{kind}/issues/{key}/comment` | |
| PUT | `/cms/scope-boards/{id}/queues/{kind}/issues/{key}/due-date` | |

Scope create/update body: см. [SCOPE-BOARD.md](./SCOPE-BOARD.md).

`GET /cms/scope-boards/{id}` возвращает `snapshot.flow_pace` (если команда включена и был refresh с changelog). См. [SCOPE-BOARD.md § AI пульс спринта](./SCOPE-BOARD.md#ai-пульс-спринта-flow_pace).

### Audit / users

| Method | Path | Permission |
|---|---|---|
| GET | `/cms/events` | `cms.events.view` |
| GET | `/cms/users` | `cms.users.view` |
| DELETE | `/cms/users/{id}` | `cms.web_participants.delete` + confirm_name + team scope |

### Standups (daily records)

Один опубликованный дейлик на команду в день. Payload: roster участников + work items по трекам `yesterday` / `today` / `blocker` (ручной текст задачи, опциональный Jira key, локальный срок, статус, комментарий). Срок из прошлых дейликов — подсказка через lookup, не автозаполнение.

| Method | Path | Permission |
|---|---|---|
| GET/PUT | `/cms/standup-rosters/{team_id}` | view / `cms.standups.manage` |
| GET/POST | `/cms/standups` | `cms.standups.view` / manage |
| GET/PATCH/DELETE | `/cms/standups/{id}` | view / manage |
| POST | `/cms/standups/{id}/sync-roster` | manage (409 если published) |
| POST | `/cms/standups/{id}/publish` | manage (при первой публикации ставит AI job в очередь) |
| POST | `/cms/standups/{id}/analyze` | manage (`?async=1`, `?force=1`; только published) |
| GET | `/cms/standups/{id}/analyze/jobs/{job_id}` | manage (poll AI job) |
| GET | `/cms/standups/local-due-hints/{issue_key}` | view (`team_id`, `before` query) |
| GET | `/cms/standups/jira-issues/{issue_key}` | view (summary из Jira) |

Поле `ai_summary` (JSONB) заполняется после LLM-дайджеста: `summary`, `changed`, `unchanged`, `watch`, `done`, `in_progress`, `blockers`, `risks`, `focus`. AI сравнивает с предыдущим опубликованным дейликом команды. При успехе сервер отправляет HTML-сводку в Telegram (`TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`).

UI: `web/src/features/cms/standups/`, route `/cms/standups`.

---

## retro_router

### Public (token)

| Method | Path |
|---|---|
| POST | `/retro/join` |
| GET | `/retro/state/{token}` |
| POST | `/retro/card` |
| POST | `/retro/vote` |
| WS | `/retro-ws/{token}` |

### CMS

| Method | Path | Permission |
|---|---|---|
| GET/POST | `/cms/retros` | view / manage |
| GET/PUT/DELETE | `/cms/retros/{id}` | view / manage |
| POST | `/cms/retros/{id}/invite` | manage |
| POST | `/cms/retros/{id}/open-section` | manage |
| POST | `/cms/retros/{id}/close-section` | manage |
| POST | `/cms/retros/{id}/phase` | `{target: "voting"\|"discussing"}` |
| CRUD | `/cms/retros/{id}/groups[/{id}]` | manage |
| CRUD | `/cms/retros/{id}/action-items[/{id}]` | manage |
| POST | `/cms/retros/{id}/finalize` | manage |
| POST | `/cms/retros/{id}/analyze` | `cms.retro.analyze` |
| GET | `/cms/retros/{id}/analyze/jobs/{job_id}` | poll |

---

## HTTP status codes (conventions)

| Code | Когда |
|---|---|
| 401 | нет/просрочен CMS token |
| 403 | нет permission / team scope |
| 404 | record или web/retro token not found |
| 409 | session mutation conflict / immutable retro |
| 422 | Pydantic validation |
| 429 | rate limit |
| 502 | upstream Jira/LLM failure |
| 503 | CMS store unavailable / scope refresh Jira failure |

---

## Frontend API modules

`web/src/features/cms/api/cmsClient.ts`:

| Export | Backend prefix |
|---|---|
| `cmsAuthApi` | `/cms/auth/*` |
| `cmsScopeApi` | `/cms/scope-boards/*` |
| `cmsRetroApi` | `/cms/retros/*` |
| `cmsStandupsApi` | `/cms/standups/*`, `/cms/standup-rosters/*` |
| `cmsPlannerApi` | `/cms/sprint-plans/*` |
| `cmsAccessApi` | `/cms/access/*` |
| `cmsTasksApi` | `/cms/sessions/{id}/tasks/*` |

Manager cockpit использует `appUrl()` напрямую (не cmsClient).
