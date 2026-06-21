# Shared Python library delivery

**Decision:** `planning-poker-python-lib` is installed via **git tag** in service Dockerfiles and `requirements.txt`. Private PyPI is not used.

## Package

- Repo: [shulzpavel/planning-poker-python-lib](https://github.com/shulzpavel/planning-poker-python-lib) — **current pin: `v0.1.2`**
- Import path: `planning_poker_common`
- Stdlib-only pure modules: `jira/text`, `jira/role_contributors`, `scope/domain`, `ports/jira_client`

## Pinning

```text
# requirements.txt (both backend services)
planning-poker-common @ git+https://github.com/shulzpavel/planning-poker-python-lib@v0.1.2
```

Docker build (multi-stage or build-arg):

```dockerfile
ARG COMMON_LIB_REF=v0.1.0
RUN pip install "planning-poker-common @ git+https://github.com/shulzpavel/planning-poker-python-lib@${COMMON_LIB_REF}"
```

## Release process

1. Merge changes to `planning-poker-python-lib` main.
2. Tag `v0.x.y` on GitHub.
3. Bump pin in jira-service and voting-service in the **same release train** when scope domain changes.
4. CI: lib repo runs pytest; service repos run integration tests against pinned tag.

## Why not copy-paste

Duplicate `scope_board.py` and `jira_text.py` between services drift within weeks. Git tag keeps a single source without operating PyPI.

## scope_board merge rule (PR-9)

Before extract to lib: **union** both copies — jira-service enrichment/retry/start_date/significance + voting queue/significance helpers. Do not take jira-only snapshot.
