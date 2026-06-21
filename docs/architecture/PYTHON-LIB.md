# Shared Python library delivery

**Decision:** `planning-poker-python-lib` is installed via **GitHub tarball tag** in `requirements.txt`. Private PyPI is not used. **Do not use `git+https://` in Docker** — slim images have no `git` binary and builds fail silently or at pip install.

## Package

- Repo: [shulzpavel/planning-poker-python-lib](https://github.com/shulzpavel/planning-poker-python-lib) — **current pin: `v0.1.2`**
- Import path: `planning_poker_common`
- Stdlib-only pure modules: `jira/text`, `jira/role_contributors`, `scope/domain`, `ports/jira_client`

## Pinning

```text
# requirements.txt (both backend services)
planning-poker-common @ https://github.com/shulzpavel/planning-poker-python-lib/archive/refs/tags/v0.1.2.tar.gz
```

Docker build — same tarball URL as in `requirements.txt` (no separate `RUN pip install git+https`):

```dockerfile
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
```

After any Dockerfile or `requirements.txt` change, run `docker build` locally (or rely on CI `docker` job) before push.

## Release process

1. Merge changes to `planning-poker-python-lib` main.
2. Tag `v0.x.y` on GitHub.
3. Bump tarball URL in jira-service and voting-service in the **same release train** when scope domain changes.
4. CI: lib repo runs pytest; service repos run `docker build` + `import planning_poker_common` smoke check.

## Why not copy-paste

Duplicate `scope_board.py` and `jira_text.py` between services drift within weeks. Git tag keeps a single source without operating PyPI.

## scope_board merge rule (PR-9)

Before extract to lib: **union** both copies — jira-service enrichment/retry/start_date/significance + voting queue/significance helpers. Do not take jira-only snapshot.
