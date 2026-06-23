# Shared Python library delivery

**Decision:** `planning_poker_common` is **vendored** into each backend service at `vendor/planning-poker-common/` and loaded via **`PYTHONPATH`** — no GitHub tarball, no private PyPI, no tokens at build time.

The standalone repo [planning-poker-python-lib](https://github.com/shulzpavel/planning-poker-python-lib) is **archived** (read-only history). Do not clone or depend on it.

## Package

- Import path: `planning_poker_common`
- Stdlib-only pure modules: `jira/text`, `jira/role_contributors`, `scope/domain`, `scope/team_questions`, `ports/jira_client`

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

1. Edit `vendor/planning-poker-common/planning_poker_common/` in **one** backend service; run pytest there.
2. Copy the same tree into the other service (default source: jira vendor):

```bash
cd planning-poker-dev
./scripts/sync-vendor-common.sh
# or, if you edited voting-service copy:
SRC=../planning-poker-voting-service/vendor/planning-poker-common ./scripts/sync-vendor-common.sh
```

3. Run `make backend-test` and `docker build` in both services before merge.

## Why vendor

Private GitHub repos need token plumbing in CI/Docker; tarball URLs fail on auth and show up in build logs. Vendoring removes network/auth from the critical path.

## scope_board merge rule

Before syncing: **union** jira enrichment/retry/start_date/significance + voting queue/significance helpers. Do not take a jira-only snapshot.
