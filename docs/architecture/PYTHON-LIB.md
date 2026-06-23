# Shared Python library delivery

**Decision:** `planning_poker_common` is **vendored** into each backend service at `vendor/planning-poker-common/` and loaded via **`PYTHONPATH`** — no GitHub tarball, no private PyPI, no tokens at build time.

## Package

- Import path: `planning_poker_common`
- Stdlib-only pure modules: `jira/text`, `jira/role_contributors`, `scope/domain`, `scope/team_questions`, `ports/jira_client`
- Optional upstream sandbox: [planning-poker-python-lib](https://github.com/shulzpavel/planning-poker-python-lib) (not required for clone/build/deploy)

## Layout (both backend services)

```text
vendor/planning-poker-common/
  pyproject.toml          # metadata only; not installed in Docker/CI
  planning_poker_common/
    jira/
    scope/
    ports/
```

Service code may re-export via `app/domain/scope_board.py`, `app/utils/jira_text.py`, etc.

## Runtime / Docker

```dockerfile
COPY vendor/planning-poker-common/ ./vendor/planning-poker-common/
ENV PYTHONPATH=/app/vendor/planning-poker-common:/app
```

`requirements.txt` does **not** reference the vendor tree — only third-party deps.

## Local tests

From a service repo:

```bash
PYTHONPATH=vendor/planning-poker-common:. python3 -m pytest -q
```

From `planning-poker-dev`:

```bash
make backend-test
```

`make backend-test` sets `PYTHONPATH` to both vendor trees automatically.

## Sync after domain changes

1. Edit and test in `planning-poker-python-lib` **or** directly in one service `vendor/`.
2. Copy the same tree into **both** services (keep copies identical):

```bash
cd planning-poker-dev
./scripts/sync-vendor-common.sh
```

3. Run `make backend-test` and `docker build` in both services before merge.

## `planning-poker-python-lib` repo — delete?

**Not required for production.** After vendoring:

- **Do not delete** until both services are merged and deployed with `vendor/`.
- **Optional:** archive the GitHub repo later, or keep it as a scratchpad for domain edits + `sync-vendor-common.sh`.
- **Remove** from `clone-all.sh` for new developers — lib ships inside jira/voting repos.

## Why vendor

Private GitHub repos need token plumbing in CI/Docker; tarball URLs fail on auth and show up in build logs. Vendoring removes network/auth from the critical path.

## scope_board merge rule

Before syncing: **union** jira enrichment/retry/start_date/significance + voting queue/significance helpers. Do not take a jira-only snapshot.
