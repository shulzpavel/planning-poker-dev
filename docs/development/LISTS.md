# List loading and pagination

## Intent (project standard)

**Long lists load progressively, not all at once.**

1. The **first request** returns at most **10 items** plus pagination metadata.
2. **No full-list fetch** happens until the user clicks **«Показать ещё»** (or an equivalent explicit action).
3. Each «Показать ещё» loads **the next page only** (cursor-based), appends to what is already shown, and updates `hasMore` / counter.

This keeps initial page load, JSON payloads, and DOM size predictable on large boards and admin tables.

---

## Two patterns

### 1. Server-backed lists (preferred)

Use when data comes from a **dedicated list endpoint** (`GET /cms/...` with cursor).

| Layer | Tool |
|---|---|
| API contract | `{ items, next_cursor, limit, total? }` |
| Frontend hook | `useCmsList` → `useProgressiveList` |
| UI footer | `LoadMoreFooter` / `ScopeIncrementalFooter` |
| Page size | `LIST_PAGE_SIZE` (= **10**) in query `limit` |

**Examples:** sessions, users, audit events, web tokens, session tasks/participants, manager finished-session tasks.

```text
User opens list     → GET ...?limit=10
User clicks «ещё»   → GET ...?limit=10&cursor=<opaque>
```

`useProgressiveList` may **prefetch** the next page in the background after the first page renders (UX optimization). That is still one page per HTTP request — never the full collection in a single response.

### 2. Snapshot-embedded lists (interim)

Use when items are **already inside a parent document** (e.g. `scope-board.snapshot` after refresh or `GET /cms/scope-boards/{id}`).

| Layer | Tool |
|---|---|
| Data source | Parent payload (board snapshot, report section, flow-pace chart) |
| Frontend hook | `useListDisplayWindow` (`useIncrementalList` alias) |
| UI footer | `ScopeIncrementalFooter` |
| Window size | `LIST_PAGE_SIZE` (= **10**) |

**Important:** this pattern only **windows the DOM** — the full array is still present in the parent JSON. For very large boards, prefer splitting into a **sub-resource API** (pattern 1) so the initial board load stays slim.

**Examples (current):** flow-pace donut details, report columns, priority queue ranked rows, activity feed, visual dashboard issue lists.

**Roadmap:** heavy scope lists (section issues, flow-pace task detail) → `GET /cms/scope-boards/{id}/…?limit=10&cursor=…`.

---

## Constants

| Constant | Value | Where |
|---|---|---|
| `LIST_PAGE_SIZE` | 10 | `web/src/shared/listPaging.ts` |
| `CMS_PAGE_LIMIT` | 10 | `web/src/app/config.ts` (API query default) |
| Backend `DEFAULT_LIMIT` | 50 | `cms_store.py` — used only when client omits `limit`; **clients should always send `limit=10`** |

---

## UI checklist

- [ ] First paint shows ≤10 rows/cards
- [ ] Footer: «Показано N из M» or «N» when total unknown
- [ ] «Показать ещё» disabled while `loadingMore`
- [ ] Empty state when `items.length === 0 && !loading`
- [ ] Error state with retry on first-page failure
- [ ] Filter/search change resets list (`reload()` / new params)

---

## Anti-patterns

- Fetching thousands of rows in one response «because cursor is hard»
- Using `useListDisplayWindow` for data that should come from a list API
- Client-side `slice` without a footer when the backend could paginate
- Auto-loading all pages in a loop without user action (except documented print/export flows)
