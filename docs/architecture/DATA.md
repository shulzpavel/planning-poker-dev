# Хранилища данных

## Redis

### Live state (без TTL)

| Key | Value |
|---|---|
| `session:{chat_id}:{topic_id\|"none"}` | Session JSON (tasks, phase, voters, …) |
| `retro:{retro_id}` | Retro JSON (sections, cards, groups, phase) |

Optimistic locking: `WATCH` + retry в `RedisSessionRepository.mutate_session()`. Конфликт → `SessionMutationConflictError` → HTTP **409**.

### Tokens (TTL 8h)

| Key | Value |
|---|---|
| `web:{token}` | `{chat_id, topic_id}` |
| `web_participant:{token}:{pid}` | `{name, user_id, role}` |
| `web_retro:{token}` | `{retro_id}` |
| `retro_participant:{token}:{pid}` | participant identity |

### CMS session (TTL 24h, absolute expiry)

| Key | Value |
|---|---|
| `cms_token:{token}` | `{admin_id, username, ip, issued_at, expires_at, token_version}` |

Redis TTL совпадает с `CMS_TOKEN_TTL_SECONDS` (garbage collection). **Sliding refresh отключён** — срок жизни фиксируется в `expires_at` при login. `token_version` сверяется с `cms_admin_accounts.token_version` (инкремент при смене пароля).

### AI jobs (TTL 1h)

| Key | Value |
|---|---|
| `ai_job:{job_id}` | job record (status, phase, result, error) |
| `ai_job_dedupe:{kind}:{resource_key}` | active job_id для dedupe |

Stale running job (>300s без heartbeat) → auto-fail, dedupe cleared.

### Pub/sub channels

| Channel | Subscribers |
|---|---|
| `session_events:{chat_id}:{topic_id}` | WS `/ws/{token}` |
| `retro_events:{retro_id}` | WS `/retro-ws/{token}` |

### Rate limit keys

Pattern `rl:{scope}:{identifier}` — atomic INCR+EXPIRE. Fail-open если Redis недоступен.

Полный список defaults: [../development/GUIDE.md#rate-limits](../development/GUIDE.md#rate-limits).

---

## Postgres

Schema создаётся в `cms_store.ensure_schema()`. Pool: asyncpg min=1 max=5.

### Ключевые таблицы

#### `cms_sessions`

Live session mirror + CMS index.

| Column | Notes |
|---|---|
| `session_key` | UNIQUE |
| `chat_id`, `topic_id` | session identity |
| `tasks_version` | optimistic concurrency |
| `team_id` | FK → cms_teams |
| `raw JSONB` | canonical domain JSON |

#### `cms_scope_boards`

| Column | Notes |
|---|---|
| `month` | YYYY-MM |
| `capacity_sp`, `capacity_sp_dev/test` | ёмкость |
| `workload_mode` | `sp` \| `sp_dev_test` |
| `report_type` | `monthly` \| `release` |
| `scope_sections JSONB` | JQL sections config |
| `plan_jql`, `unplan_jql`, `todo_jql`, `test_jql` | legacy + queues |
| `release_queries JSONB` | extra release JQLs |
| `plan_epic_key` | Jira key для AI export |
| `snapshot JSONB` | built by refresh |
| `ai_summary JSONB` | current AI analysis |
| `ai_summary_history JSONB` | cache by snapshot hash |
| `layout_order JSONB` | UI block order |
| `team_id` | team scope |

#### `cms_retros`

| Column | Notes |
|---|---|
| `status` | `draft` \| `live` \| `done` |
| `config JSONB` | sections, votes_per_person, timers |
| `snapshot JSONB` | anonymised after finalize |
| `ai_summary JSONB` | post-analyze |

#### RBAC

`cms_permissions`, `cms_pages`, `cms_roles`, `cms_role_permissions`, `cms_admin_accounts`, `cms_admin_roles`, `cms_admin_teams`, `cms_teams`.

---

## Concurrency contracts

### Session mutation

Клиент может передать `expected_version` (tasks_version). Backend использует Redis WATCH.

**Frontend best practice:** при 409 — retry fetch state + повтор mutation.

### Scope refresh

Atomic replace snapshot в Postgres. При Jira partial failure snapshot **не меняется**.

### AI job dedupe

Один active job на `(kind, resource_key)`. Повторный `POST …/analyze?async=1` вернёт тот же `job_id`.
