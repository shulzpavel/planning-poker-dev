# Scope board — контракты и pipeline

Domain: `voting-service/app/domain/scope_board.py`  
HTTP: `voting-service/services/voting_service/cms_api.py`  
Frontend types: `web/src/features/cms/api/cmsClient.ts`

---

## Report types

```python
ScopeReportType = "monthly" | "release"

RELEASE_SCOPE_TEAM_SLUGS = {"igaming-ios", "igaming-android"}
```

`infer_scope_report_type(team_slug)` → `"release"` для mobile slugs, иначе `"monthly"`.

Release boards: один блок «Текущий релиз» + `release_context` в snapshot.

---

## Board config (create / update)

```typescript
// cms_api.py Pydantic mirrors in cmsClient.ts
{
  name: string
  month: string              // YYYY-MM
  capacity_sp: number
  capacity_sp_dev?: number   // when workload_mode = sp_dev_test
  capacity_sp_test?: number
  workload_mode: "sp" | "sp_dev_test"
  scope_sections: [{
    id?: string
    name: string
    jql: string
    kind: "planned" | "unplanned"
    order: number            // 0..99
  }]
  plan_jql?: string          // legacy flat (still supported)
  unplan_jql?: string
  todo_jql?: string
  test_jql?: string
  release_queries?: [{ jql, label?, comment? }]
  plan_epic_key?: string     // Jira key for AI export, e.g. FLEX-123
  team_id?: number           // create only
}
```

---

## Refresh pipeline

`POST /cms/scope-boards/{id}/refresh`

```text
1. Auth: cms.planner.view + team scope
2. Rate limit: actor (30/h) + board (12/h)
3. Fetch scope sections ──parallel──► jira-service POST /search/scope
4. Fetch todo_jql, test_jql (enrich_changelog=true)
5. If report_type=release: fetch release JQLs + version metadata
6. Failure policy:
   - all JQL failed → 503, snapshot unchanged
   - partial failure + had previous snapshot → 503, snapshot unchanged
7. compute_scope_metrics_from_sections()
8. build_scope_snapshot() + delta/events
9. merge_priority_queue() — preserve manual order/comments
10. copy manual_questions, top_items, todo_items, report_comments from prev
11. store.save_scope_board_snapshot()
12. audit cms.scope_board.refresh
```

**Best practice:** не менять snapshot вручную в Postgres — только через refresh или PATCH endpoints.

---

## Snapshot shape

```typescript
interface ScopeBoardSnapshot {
  sections: ScopeSection[]       // planned/unplanned + issues
  plan_issues: ScopeBoardIssue[] // legacy flat derived
  unplan_issues: ScopeBoardIssue[]
  metrics: ScopeBoardMetrics
  report: ScopeReport
  jira_role_fields_configured: { front, back, qa: boolean }
  refreshed_at: string             // ISO8601
  delta?: ScopeRefreshDelta
  events?: ScopeRefreshEvent[]
  refresh_log?: [...]              // last 15 refreshes
  manual_questions?: [...]
  resolved_questions?: [...]
  top_items?: [...]
  todo_items?: [...]
  report_comments?: Record<issueKey, string>
  priority_queues?: {
    todo: ScopePriorityQueue
    test: ScopePriorityQueue
  }
  release_context?: ScopeReleaseContext  // release boards only
  jira_fetch_warnings?: string[]
}
```

### Metrics (`metrics`)

Ключевые поля:

| Field | Type | Meaning |
|---|---|---|
| `workload_mode` | `sp` \| `sp_dev_test` | режим ёмкости |
| `capacity_sp[_dev\|_test]` | number | заданная ёмкость |
| `plan_sp`, `unplan_sp` | number | SP в plan/unplan |
| `buffer_sp` | number | запас |
| `intake_status` | `ok` \| `warning` \| `stop` | можно ли брать новый scope |
| `plan_by_role` | dict | active horizon workload |
| `plan_by_role_sprint` | dict | sprint horizon workload |
| `scope_creep_count` | number | |
| `unestimated_tasks` | array | force warning |

Intake rules (`sp` mode):
- buffer ≤ 0 → `stop`
- buffer ≤ 20% capacity → `warning`
- unestimated tasks → at least `warning`

### Issue in snapshot (`ScopeBoardIssue`)

Нормализация: `normalize_scope_issue()` из jira-service `ScopeIssueResponse`.

Frontend mirror: `cmsClient.ts` lines ~374–443 — key, summary, story_points, story_points_dev/test, status, role_contributors, plan_status, sprints, etc.

---

## Priority queues

Kinds: `"todo"`, `"test"`.

```typescript
{
  order: string[]           // issue keys, manual DnD
  issues: ScopeBoardIssue[]
  history: [{
    at, kind: "reorder"|"comment"|"refresh"|"appeared",
    actor?, issue_key?, ...
  }]
  filter_seen_at: Record<key, iso>
}
```

Reorder: `POST /queues/{kind}/reorder` body `{order: string[]}`.

---

## Scope AI

### Analyze

```
POST /cms/scope-boards/{id}/analyze?async=1
→ sync: { ai_summary, board, cached? }
→ async: { job_id, is_new? }
```

Poll: `GET …/analyze/jobs/{job_id}` → `AiJobResponse`.

### Summary schema (LLM output)

```typescript
interface ScopeAiSummary {
  health: "green" | "yellow" | "red"
  summary: string
  whats_good: string[]
  whats_bad: string[]
  whats_critical: string[]
  buffer_status: "ok" | "tight" | "critical" | "overfilled" | "unknown"
  blockers: [{ title, severity, detail, issue_keys }]
  recommendations: [{ text, impact }]
  focus_now: string[]
  // + report_assessment, role_workload_assessment, queue_insights, ...
  jira_export?: {
    status: "ok" | "error" | "pending"
    error?: string
    comment_id?: string
    summary_hash?: string
  }
}
```

Validation: `scope_ai_llm.py`. Stored in `cms_scope_boards.ai_summary`.

### Cache

`find_cached_scope_summary(board, snapshot.refreshed_at)` — если тот же snapshot уже анализировали, LLM skip (`cached: true`). Jira export всё равно может обновиться.

### Jira export

Если `plan_epic_key` задан → ADF comment на epic после analyze.

Module: `scope_ai_jira_export.py`. Skip if summary hash unchanged.

Frontend badge: `scopeAiJiraExport.tsx`.

---

## Layout

`PATCH /cms/scope-boards/{id}/layout`

```json
{ "layout_order": ["capacity", "ai", "report", "queues", ...] }
```

Block keys defined in frontend `ScopeBoardShell.tsx`.

---

## Sequence: refresh → analyze → Jira export

```mermaid
sequenceDiagram
  participant UI as web ScopeBoardShell
  participant VS as voting-service
  participant JS as jira-service
  participant LLM as Anthropic
  participant Jira as Jira Cloud

  UI->>VS: POST /scope-boards/{id}/refresh
  VS->>JS: POST /search/scope (per section)
  JS->>Jira: JQL search + enrich
  JS-->>VS: ScopeIssueResponse[]
  VS->>VS: build_scope_snapshot()
  VS-->>UI: board with snapshot

  UI->>VS: POST /scope-boards/{id}/analyze?async=1
  VS->>VS: get_or_create_job(scope, board:{id})
  VS->>LLM: scope prompt + metrics context
  LLM-->>VS: ScopeAiSummary JSON
  VS->>VS: save ai_summary
  VS->>JS: POST /issue/{epic}/comment/adf
  JS->>Jira: create/update ADF comment
  VS-->>UI: job_id
  UI->>VS: poll GET …/analyze/jobs/{job_id}
  VS-->>UI: status=done, result.ai_summary
```

---

## Tests

| Repo | File | Covers |
|---|---|---|
| voting-service | `tests/test_scope_ai_*.py` | AI prompt, export |
| voting-service | `tests/test_infer_scope_report_type.py` | report types |
| voting-service | `tests/test_cms_scope_fetch.py` | refresh fetch |
| jira-service | `tests/test_scope_board.py` | enrichment shape |
