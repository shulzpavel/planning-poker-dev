# Авторизация и RBAC

## CMS cookie auth

### Login

```
POST /api/v1/cms/auth/login
Body: { username, password }
→ Set-Cookie: cms_token=<uuid>; HttpOnly; Secure (prod); SameSite=Lax
→ { id, username, display_name, permissions, roles, pages, teams, ... }
```

### Проверка на каждом запросе

1. Cookie `cms_token` или header `Authorization: Bearer <token>`.
2. Redis lookup: `cms_token:{token}` → `{admin_id, username, ip, issued_at, expires_at, token_version}`.
3. Postgres: `get_admin_principal(admin_id)` — join roles, permissions, pages, teams.
4. **Absolute expiry:** token отклоняется, если `now >= expires_at` (sliding TTL **не** продлевает сессию).
5. **Token version:** `token_version` в Redis должен совпадать с `cms_admin_accounts.token_version`; при смене пароля версия инкрементируется и все старые токены инвалидируются.

401 если token missing / expired / version mismatch / admin deactivated.

**Cookie Secure:** по умолчанию `Secure=true` вне dev (`APP_ENV=dev` или явный `CMS_COOKIE_SECURE=false` для local HTTP). Prod: `CMS_COOKIE_SECURE=true` в `docker-compose.prod.yml`.

**Frontend:** `credentials: "include"` в `cmsFetch()`. LocalStorage hint `planning_poker_cms_auth` — только UX-флаг, не секрет.

### Bootstrap admin (one-time)

При старте `voting-service` вызывает `ensure_access_defaults(CMS_USERNAME, CMS_PASSWORD)`:

- если учётки с таким `username` **нет** — создаётся superadmin с паролем из env и ролью `superadmin`;
- если учётка **уже есть** — `ON CONFLICT DO NOTHING`: пароль, `is_active`, `is_superuser` **не перезаписываются**.

Следствия:

- ротация пароля и деактивация bootstrap-админа переживают рестарт;
- скомпрометированный `CMS_PASSWORD` в env **не** восстанавливает доступ после смены пароля в CMS;
- дальнейшее управление — только через CMS Access (`/cms/access`).

Env: `CMS_USERNAME`, `CMS_PASSWORD` (см. [GUIDE.md](../development/GUIDE.md#environment-variables)).

### Logout

```
POST /api/v1/cms/auth/logout
→ удаляет cms_token из Redis, clears cookie
```

---

## RBAC

### Principal

```python
@dataclass(frozen=True)
class CmsPrincipal:
    id: int
    username: str
    is_superuser: bool
    permissions: frozenset[str]
    team_ids: frozenset[int]
    pages: tuple[dict, ...]   # навигация CMS
    theme_preference: "dark" | "light" | "system"

    def can(self, permission: str) -> bool:
        return self.is_superuser or permission in self.permissions
```

Источник: `services/voting_service/_http_shared.py`.

### Permissions (canonical keys)

| Key | CMS раздел |
|---|---|
| `cms.overview.view` | Сводка |
| `cms.sessions.view` | Сессии (read) |
| `cms.planner.view` | Калькулятор + **Отчёты (scope)** |
| `cms.retro.view` | Ретро (read) |
| `cms.retro.manage` | Ретро (write) |
| `cms.retro.analyze` | AI analyze retro |
| `cms.users.view` | Участники |
| `cms.events.view` | Журнал |
| `cms.access.view` | Доступы (read) |
| `cms.access.manage` | Доступы (write) |
| `cms.tasks.manage` | CRUD задач в CMS sessions |
| `app.sessions.manage` | Cockpit + `/app/*` |
| `cms.web_participants.delete` | Hard delete участников |

Определения: `services/voting_service/cms_rbac.py`.

### Dependency pattern (backend)

```python
# любой logged-in admin
principal: CmsPrincipal = AuthDep

# конкретное permission
principal = Depends(require_permission(PERM_PLANNER_VIEW))

# manager cockpit — permission only
principal = Depends(_manager_dep)  # PERM_APP_SESSIONS_MANAGE

# manager cockpit — session-scoped (permission + team check)
principal = Depends(_require_manager_session)
```

403 если `not principal.can(permission)`.
404 если сессия принадлежит чужой команде (`assert_record_access` — без утечки существования).

Destructive CMS endpoints (`DELETE /cms/tokens/{id}`, `DELETE /cms/users/{id}`) резолвят родительскую сессию и проверяют team scope до мутации. Для участника проверяются **все** связанные `team_id` сессий (`assert_user_sessions_access`).

---

## Team scope

Каждая CMS-запись привязана к `team_id` (nullable для legacy).

| Actor | Видит |
|---|---|
| superuser | всё |
| admin без teams | только `team_id IS NULL` |
| admin с teams | записи где `team_id IN actor.team_ids` |

Проверка: `assert_record_access(actor, row)` в `cms_team_access.py`.  
Для hard-delete участника: `assert_user_sessions_access(actor, team_ids)` — все связанные команды должны быть доступны актору.

При создании: `resolve_create_team_id(actor, requested_team_id)`.

**Best practice:** новые фичи CMS всегда фильтруют по team. Не добавлять endpoints без team check.

---

## Public token auth (voting / retro)

### Voting

```
POST /api/v1/web/token     → { token }   (manager mints via /app/.../invite)
POST /api/v1/web/join      → { token, email, role }
GET  /api/v1/web/state/{token}
POST /api/v1/web/vote
WS   /api/v1/ws/{token}
```

Redis:
- `web:{token}` → `{chat_id, topic_id}` TTL **8h**
- `web_participant:{token}:{pid}` → `{name, user_id, role}` TTL **8h**

Email валидируется: `participant_identity.validate_participant_email` (corporate domain).

### Retro

```
POST /api/v1/retro/join
GET  /api/v1/retro/state/{token}
POST /api/v1/retro/card | /vote
WS   /api/v1/retro-ws/{token}
```

Redis: `web_retro:{token}`, `retro_participant:{token}:{pid}` TTL **8h**.

404 если token expired/missing.

---

## Login rate limits

| Limit | Default | Key |
|---|---|---|
| per username+IP | 5 / 15 min | `cms_login_fail:{username}:{ip}` |
| per IP | 20 / 15 min | `rl:login:ip:{ip}` |

429 с localized message.
