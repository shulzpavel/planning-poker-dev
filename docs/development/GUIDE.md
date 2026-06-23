# Руководство разработчика

---

## Best practices

### Границы сервисов

| Делай | Не делай |
|---|---|
| Jira calls только через jira-service | `requests`/`aiohttp` напрямую к Atlassian из voting-service |
| `app/adapters/jira_service_client.py` — единственный Jira adapter в voting | Локальный `JiraHttpClient` / `gitlab_http` в voting-service (удалён) |
| Бизнес-логику в `app/domain/` | Сложные вычисления metrics в React components |
| Reuse `app.state.http_session` | Новый `ClientSession` на каждый request |
| Team scope на каждом CMS endpoint | Endpoints без `assert_record_access` |
| Optimistic concurrency + 409 retry | Silent overwrite session state |
| Typed contracts в Pydantic + `cmsClient.ts` | Ad-hoc dict shapes без types |

### Backend changes

1. **Новый CMS endpoint** → permission constant в `cms_rbac.py`, `require_permission()`, team check, audit event.
2. **Новое поле scope snapshot** → `normalize_scope_issue()` + `ScopeBoardIssue` в `cmsClient.ts` + тест.
3. **Jira enrichment** → jira-service first, потом voting-service domain.
4. **Breaking API change** → обновить frontend + docs + call out in PR.

### Frontend changes

1. Все CMS calls через `cmsFetch` / `cmsScopeApi` / etc. с `credentials: "include"`.
2. Loading / error / empty / success states для каждого async action.
3. AI async → `pollAiJob`, не busy-wait loop в компоненте.
4. 401 → redirect login (`clearCmsAuthHint`).
5. 409 session conflict → refetch + retry once.

### Mobile CMS layout (`< lg`)

Operations screens (planner, scope, retro, sessions) share mobile-only building blocks in `src/features/cms/components/CmsPrimitives.tsx`:

| Primitive | Role |
|---|---|
| `MobilePageHero` | Edge-to-edge summary strip with stats and primary action (`lg:hidden`) |
| `MobileFeatureCard` | List card with accent border, metrics grid, open/delete actions |
| `MobileFilterBar` | Horizontal scroll wrapper for `TeamFilter` on phone |
| `MobileMetricTile` | Compact stat tile used inside hero/detail strips |

Navigation:

- Desktop (`lg+`): tab strip in `CmsShell` header.
- Mobile: `HeaderMenuButton` opens `BottomSheet` with grouped `SheetItem`s; footer actions use `SheetFooterActions` + `SheetActionButton` (logout stays pinned — scroll only the nav list).

Routing:

- Nested CMS URLs (`/cms/scope/:id`, `/cms/planner/new`) must **not** remount the whole CMS shell. Use `resolveCmsSectionKey()` / `resolveAppTransitionKey()` from `navigation.ts` as the `RouteTransition` key (see `CmsShell.tsx`, `App.tsx`).

Bottom sheet gestures (`BottomSheet`, CMS/manager menus):

- Motion math lives in `src/design-system/sheetMotion.ts` (durations/easing from `motionTokens`, thresholds as ratios of sheet height).
- Drag + enter/close animation is centralized in `useBottomSheetDrag.ts` with window-level `pointermove`/`pointerup` listeners — do not reimplement per screen.
- Mobile: slide up on open, drag handle + title zone to dismiss, backdrop dims with drag offset. Desktop (`md+`): centered dialog with scale-in only.

When adding a new CMS list screen, keep desktop `SectionHeader` + table in `hidden lg:block` and mirror the list with `MobileFeatureCard` in a `lg:hidden` grid. Pass `onActivate` on cards so tapping the title opens the record.

### Button intents (`Button`, `SheetActionButton`)

Use semantic `intent` instead of raw `variant` for actions. Mapping lives in `src/design-system/components.tsx` (`resolveButtonVariant`).

| Intent | Variant | Use for |
|---|---|---|
| `open`, `create`, `add`, `save`, `apply`, `primary` | primary (blue) | Open record, create entity, persist form |
| `success` | success (green) | Confirm positive bulk action |
| `back`, `cancel`, `neutral`, `refresh`, `reset`, `edit`, `more` | secondary | Dismiss, filter reset, Jira refresh, reorder, pagination |
| `delete`, `danger`, `finish` | danger (red) | Delete, finish session, destructive confirm |

Rules:

- List/card primary CTA: `intent="open"` (mobile + desktop).
- List destructive secondary: `intent="delete" size="sm"`.
- **`intent="delete"` always opens a built-in `ConfirmDialog`** («Точно удалить?» by default). New delete buttons get protection automatically — no manual wiring.
- Override copy per entity: `confirmTitle`, `confirmDescription`, `confirmLabel`.
- Stronger custom flow (e.g. hard delete with typed name): `skipDeleteConfirm` + own `ConfirmDialog`.
- Footer/form save: `intent="save"` or `intent="create"` depending on mode.
- Reserve raw `variant="ghost"` only for non-action chrome (icon toggles inside custom widgets) — prefer `intent="more"` for tertiary controls.

`SheetActionButton` passes `intent` through to `Button` — delete confirmation applies there too.

### Deploy

| Change in | Deploy |
|---|---|
| web only | `deploy-web-prod.sh` |
| voting-service or jira-service | `deploy-prod.sh` (full stack default) |
| scope CMS behavior (backend + web) | **both** voting-service + web |

**Docker / requirements**

- Shared lib: vendored under `vendor/planning-poker-common/` in each backend service; sync via `scripts/sync-vendor-common.sh` (see [PYTHON-LIB.md](../architecture/PYTHON-LIB.md)).
- After Dockerfile or `requirements.txt` change: run `docker build` locally before push; CI also runs `docker build` + `import planning_poker_common` smoke check.

**Maintenance banner during deploy**

Parallel `deploy-service-prod.sh` (jira + voting) uses Redis ref-count (`system:maintenance:refcount`). Banner stays until the last deploy finishes or any deploy exits (success or failure). See [PRODUCTION.md](../../infra/deploy/PRODUCTION.md).

---

## Где менять код

| Задача | Repo | Path |
|---|---|---|
| Scope UI blocks | web | `src/features/cms/scope/**` |
| Scope metrics / intake | voting-service | `app/domain/scope_board.py` |
| Scope refresh HTTP | voting-service | `services/voting_service/cms_api.py` |
| Scope AI prompt | voting-service | `services/voting_service/scope_ai_llm.py` |
| Scope AI → Jira | voting-service | `services/voting_service/scope_ai_jira_export.py` |
| Jira enrichment | jira-service | `app/adapters/jira_http.py`, `app/utils/*` |
| Session voting flow | voting-service | `app_api.py`, `web_api.py`, `app/domain/*` |
| Retro domain | voting-service | `app/domain/retro.py`, `retro_api.py` |
| RBAC definitions | voting-service | `cms_rbac.py` |
| CMS navigation | web | `src/features/cms/navigation.ts` |
| CMS list grouping by team | web | `src/features/cms/components/teamGrouping.ts`, `TeamGroupedSections.tsx` |
| Deploy / Caddy | dev | `infra/caddy/`, `infra/deploy/` |
| CI Telegram alerts | dev | `.github/workflows/ci-notify-*.yml` |

---

## Error handling

### Backend pattern

```python
raise HTTPException(status_code=403, detail="Недостаточно прав")
```

Domain exceptions with status:
- `SessionMutationConflictError` → global handler → **409**
- `LlmScopeError`, `LlmSummaryError`, `LlmRetroError` → `HTTPException(exc.status_code, exc.message)`
- `RetroError` → same
- `RateLimitExceeded` → **429** with RU message

### Frontend pattern

```typescript
import { ApiError } from "../../../shared/api/http";

try {
  await cmsScopeApi.refresh(id);
} catch (err) {
  if (err instanceof ApiError) {
    if (err.status === 429) showToast(err.message);
    if (err.status === 503) showToast("Jira недоступна");
  }
}
```

### Status code cheat sheet

| Code | Action (frontend) |
|---|---|
| 401 | clear auth hint, redirect `/cms` login |
| 403 | show permission error |
| 404 | show not found / expired token |
| 409 | retry mutation after refetch |
| 429 | show rate limit message, disable button temporarily |
| 502/503 | show dependency failure, preserve local state |

List pagination (first page = 10 items, cursor on «Показать ещё»): [LISTS.md](./LISTS.md).

---

## Rate limits

Implementation: `services/voting_service/rate_limit.py` (Redis INCR+EXPIRE, fail-open).

| Scope | Env (default) | Window | Key pattern |
|---|---|---|---|
| CMS login (user+IP) | `CMS_LOGIN_MAX_ATTEMPTS=5` | 900s | `cms_login_fail:{user}:{ip}` |
| CMS login (IP) | `CMS_LOGIN_IP_MAX_ATTEMPTS=20` | 900s | `rl:login:ip:{ip}` |
| Web token mint | `WEB_TOKEN_RATE_LIMIT_MAX=10` | 60s | `rl:web_token:ip:{ip}` |
| Web join | `WEB_JOIN_RATE_LIMIT_MAX=30` | 60s | `rl:web_join:ip:{ip}` |
| Web vote | `WEB_VOTE_RATE_LIMIT_MAX=30` | 60s | `rl:web_vote:participant:{pid}` |
| Manager invite | `APP_INVITE_RATE_LIMIT_MAX=30` | 60s | `rl:app_invite:actor:{user}` |
| Task AI summary | `AI_SUMMARY_RATE_LIMIT_MAX=20` | 3600s | `rl:ai_summary:actor:{user}` |
| Scope refresh (actor) | `SCOPE_REFRESH_RATE_MAX=30` | 3600s | `rl:scope_refresh:actor:{user}` |
| Scope refresh (board) | `SCOPE_REFRESH_BOARD_RATE_MAX=12` | 3600s | `rl:scope_refresh:board:{id}` |
| Scope AI | `SCOPE_AI_RATE_MAX=20` | 3600s | `rl:scope_ai:actor:{user}` |
| Retro join | `RETRO_JOIN_RATE_MAX=30` | 60s | IP + token |
| Retro card | `RETRO_CARD_RATE_MAX=60` | 60s | per user per token |
| Retro vote | `RETRO_VOTE_RATE_MAX=120` | 60s | per user per token |
| Retro AI | `RETRO_AI_RATE_MAX=20` | 3600s | `rl:retro_ai:actor:{user}` |

jira-service itself has no rate limits.

---

## Environment variables

### Required for prod

```bash
# Infra
POSTGRES_DB, POSTGRES_USER, POSTGRES_PASSWORD
APP_DOMAIN, ACME_EMAIL
SITE_ALLOWED_IPS, SITE_IP_WHITELIST_ENABLED

# CMS bootstrap (one-time seed on first startup; see docs/architecture/AUTH.md)
CMS_USERNAME, CMS_PASSWORD

# Jira
JIRA_URL, JIRA_USERNAME, JIRA_API_TOKEN
STORY_POINTS_FIELD
JIRA_DEMO_FALLBACK=false

# CORS
CORS_ORIGINS, JIRA_SERVICE_CORS_ORIGINS
WEB_UI_URL

# AI (if using AI features)
ANTHROPIC_API_KEY
```

Full list: `.env.example`, `infra/deploy/prod.env.example`.

### Per-service (compose injects)

**voting-service:** `REDIS_URL`, `POSTGRES_DSN`, `JIRA_SERVICE_URL`, `ANTHROPIC_*`, `TELEGRAM_*`, rate limit overrides.

**jira-service:** `JIRA_*`, `JIRA_SP_*_FIELD`, `JIRA_*_ASSIGNEE_FIELD`, `JIRA_CACHE_MAX_ITEMS`.

**web (build arg):** `VITE_API_BASE`.

---

## Testing

### From planning-poker-dev

```bash
make voting-test       # voting-service pytest
make jira-test         # jira-service pytest
make backend-test      # voting + jira pytest
make frontend-test     # web vitest
make frontend-e2e      # Playwright
make check             # backend-test + frontend-test + build + compileall + compose validate
```

### voting-service

```bash
cd planning-poker-voting-service
PYTHONPATH=. python -m pytest -q
PYTHONPATH=. python -m pytest tests/test_scope_ai_jira_export.py -v
```

Key test areas:
- `test_scope_*.py`, `test_scope_ai_*`
- `test_retro_*`, `test_ai_jobs.py`
- `test_cms_rbac.py`, `test_cms_team_scope.py`, `test_cms_destructive_team_scope.py`, `test_cms_bootstrap_admin.py` (needs `POSTGRES_DSN`)
- `test_web_api.py`, `test_rate_limit.py`

`pytest.ini`: `asyncio_mode = auto`.

### jira-service

```bash
cd planning-poker-jira-service
PYTHONPATH=. python -m pytest -q
PYTHONPATH=. python -m pytest tests/test_scope_board.py -v
```

### web

```bash
cd planning-poker-web
npm run test
npm run lint
npm run build
```

Tests co-located: `*.test.ts(x)` next to features.

### CI

Each repo: `.github/workflows/ci.yml`  
Shared Telegram notify: `planning-poker-dev/.github/workflows/ci-notify-*.yml`

---

## Adding a new CMS feature (checklist)

- [ ] Permission in `cms_rbac.py` + seed in `CMS_PERMISSION_DEFINITIONS`
- [ ] Page in `CMS_PAGE_DEFINITIONS` if new nav tab
- [ ] Endpoint in `cms_api.py` with `require_permission` + team scope
- [ ] Audit event via `_audit(...)`
- [ ] Pydantic request/response models
- [ ] TypeScript types + API method in `cmsClient.ts`
- [ ] UI with loading/error/empty states
- [ ] pytest for business logic
- [ ] Update [contracts/API.md](../contracts/API.md) or domain doc
- [ ] Deploy voting-service (+ web if UI changed)

---

## Debugging

### Scope refresh fails with 503

1. Check jira-service: `curl localhost:8001/health/ready`
2. Test JQL: `POST /api/v1/search/scope` with small JQL
3. voting-service logs: JQL errors, partial failure policy
4. Previous snapshot preserved — expected behavior

### WebSocket stale

1. Cloudflare WebSockets ON
2. Caddy `/api/v1/ws/` Upgrade headers
3. `docker logs voting-service | grep -i websocket`
4. Client: tab visibility reconnect

### AI job stuck

1. Redis: `GET ai_job:{job_id}` — check phase/updated_at
2. Stale after 300s → auto-fail on next request
3. Check `ANTHROPIC_API_KEY` in voting-service container
4. Scope timeout: `SCOPE_AI_TIMEOUT_SECONDS`

### CMS 401 after deploy

1. Cookie `Secure` flag vs HTTP dev
2. `CORS_ORIGINS` includes frontend origin
3. `credentials: "include"` on fetch

---

## OpenAPI vs canonical types

Swagger at `/docs` — useful for exploration, but:

- **Canonical backend types:** Pydantic models in `cms_api.py`, `_http_shared.py`, `api.py` (jira).
- **Canonical frontend types:** `cmsClient.ts`, `cmsTypes.ts`.
- Domain logic types: `scope_board.py`, `retro.py`.

При расхождении — trust source code + tests, update docs.
