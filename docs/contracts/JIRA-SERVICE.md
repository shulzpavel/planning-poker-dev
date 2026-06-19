# jira-service — контракты

**Base:** `http://jira-service:8001/api/v1` (internal)  
**Source:** `services/jira_service/api.py`, `app/adapters/jira_http.py`

---

## Принципы

1. **Stateless** — нет DB, состояние только in-memory cache.
2. **Singleton client** — `app.state.jira_client` в lifespan. Cache живёт между requests.
3. **Не exposed publicly** — только voting-service вызывает из Docker network.

---

## Search / parse

### POST `/search`

Light search для импорта в сессии.

```json
// Request
{
  "jql": "project = FLEX AND sprint in openSprints()",
  "max_results": 100,
  "force_refresh": false
}

// Response
{
  "issues": [{
    "key": "FLEX-123",
    "summary": "...",
    "url": "https://.../browse/FLEX-123",
    "story_points": 5.0
  }]
}
```

### POST `/parse`

JQL **или** список ключей → тот же light shape. Используется cockpit `jira-import`.

### POST `/search/scope`

Heavy enrichment для scope boards.

```json
// Request (SearchRequest)
{
  "jql": "...",
  "max_results": 500,
  "force_refresh": true,
  "milestone_status_targets": ["Ready for Grooming"],
  "enrich_changelog": true
}

// Response
{
  "issues": [ScopeIssueResponse],
  "jira_role_fields_configured": {
    "front": true,
    "back": true,
    "qa": false
  }
}
```

---

## ScopeIssueResponse (enriched issue)

Ключевые поля (полный список в `api.py`):

| Field | Type | Notes |
|---|---|---|
| `key`, `summary`, `url` | string | |
| `story_points` | float \| null | resolved SP |
| `story_points_dev/test/front/back/qa` | float \| null | split fields |
| `status.name`, `status.category` | string | category: new/indeterminate/done |
| `issue_type`, `labels`, `priority` | | |
| `assignee`, `developer` | string | |
| `role_contributors` | dict | front/back/qa → `{name, source}` |
| `jira_role_assignees` | dict | raw Jira assignee fields |
| `plan_status`, `plan_change_reason(s)` | string / list | custom fields |
| `sprints`, `fix_versions` | list | |
| `last_comment`, `last_comment_author`, `last_comment_at` | | |
| `due_date`, `epic_key`, `parent_key` | | |
| `severity`, `final_priority` | | |

voting-service нормализует через `normalize_scope_issue()` в `scope_board.py`.

---

## Issue reads

### GET `/issue/{key}`

Basic: `{key, summary, url, story_points}`.

### GET `/issue/{key}/context`

Rich context для AI prompts:

```json
{
  "key": "FLEX-123",
  "summary": "...",
  "url": "...",
  "description": "plain text",
  "description_adf": { ... },
  "description_html": "...",
  "description_sources": ["jira", "confluence"],
  "issue_type": "Story",
  "labels": [],
  "components": [],
  "story_points": 5
}
```

---

## Writes

### PUT `/issue/{key}/story-points`

```json
{ "issue_key": "FLEX-123", "story_points": 8 }
```

### PUT `/issue/{key}/story-points/fields`

Per-role SP:

```json
{
  "issue_key": "FLEX-123",
  "fields": {
    "customfield_10022": 8,
    "customfield_10710": 3
  }
}
```

Field IDs from env: `STORY_POINTS_FIELD`, `JIRA_SP_*_FIELD`.

### PUT `/issue/{key}/due-date`

```json
{ "issue_key": "FLEX-123", "due_date": "2026-06-30" }
```

Date format: `YYYY-MM-DD`.

### POST `/issue/{key}/comment`

Plain text, 1..4000 chars.

### POST `/issue/{key}/comment/adf`

```json
{ "body": { "type": "doc", "version": 1, "content": [...] } }
```

Used by: task AI summary export, scope AI export.

### PUT `/issue/{key}/comment/{comment_id}/adf`

Update existing ADF comment (scope AI re-export).

---

## Versions (release boards)

| Method | Path |
|---|---|
| GET | `/version/{id}` |
| GET | `/version/resolve?name=...&project=...` |

→ `VersionResponse`: name, released, release_date, overdue, etc.

---

## Env vars (jira-service)

| Variable | Purpose |
|---|---|
| `JIRA_URL` | Atlassian base |
| `JIRA_USERNAME`, `JIRA_API_TOKEN` | Basic auth |
| `STORY_POINTS_FIELD` | default SP custom field |
| `JIRA_SP_DEV/TEST/FRONT/BACK/QA_FIELD` | split SP |
| `JIRA_FRONT/BACK/QA_ASSIGNEE_FIELD` | role assignees for scope |
| `JIRA_PLAN_STATUS_FIELD`, `JIRA_PLAN_CHANGE_REASON_FIELD` | scope plan metadata |
| `JIRA_DEMO_FALLBACK` | return demo data if misconfigured |
| `JIRA_CACHE_MAX_ITEMS` | in-memory cache size |
| `JIRA_RETRY_ATTEMPTS` | transient HTTP retries (default `3`) |
| `JIRA_MAX_CONCURRENT_REQUESTS` | in-flight Jira HTTP cap per client (default `6`) |
| `GITLAB_*` | optional role evidence |

---

## Demo fallback

`JIRA_DEMO_FALLBACK=true` — возвращает fixture issues. **Prod must be `false`.**

Readiness check:

```bash
curl http://localhost:8001/health/ready
# expect jira_configured: true, demo_fallback_enabled: false
```

---

## HTTP retry / rate limits

`JiraHttpClient` (`app/adapters/jira_http.py`) retries transient Jira responses (`429`, `5xx`):

- reads `Retry-After` (seconds or HTTP-date) and waits exactly that long (not capped by backoff `max_delay`);
- otherwise exponential backoff with full jitter (`0.5s` base, `60s` cap);
- caps in-flight Jira HTTP calls with `JIRA_MAX_CONCURRENT_REQUESTS` (default `6`) so parallel scope enrichment does not amplify throttling.

---

## Error contract

jira-service пробрасывает upstream Jira errors как HTTP 4xx/5xx с `detail` string.

voting-service оборачивает в 502 при proxy failure:

```python
HTTPException(502, detail=f"Jira service error: {truncated_body}")
```

---

## Tests

`jira-service/tests/`:

- `test_scope_board.py` — enrichment contract
- `test_jira_changelog.py`, `test_jira_role_contributors.py`
- `test_gitlab_*.py` — GitLab evidence
- `test_jira_service_scope_response.py` — response shape
