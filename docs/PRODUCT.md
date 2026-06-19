# Planning Poker — продуктовая документация

Planning Poker — корпоративный **delivery hub** для agile-команд: планирование спринта, месячные отчёты по scope, live-сессии оценки и ретроспективы. Продакшен: `https://planning.shults-sync.com` (доступ через VPN).

## Для кого

| Роль | Что делает в системе |
|---|---|
| **Менеджер / тимлид** | Создаёт сессии, ведёт cockpit, настраивает отчёты, закрывает ретро |
| **Участник команды** | Голосует по ссылке `/s/{token}` или участвует в ретро `/r/{token}` |
| **Администратор CMS** | Управляет доступами, командами, аудитом |

Участники web-сессий входят по корпоративному email (домен настраивается через `WEB_PARTICIPANT_EMAIL_DOMAIN`).

---

## Четыре модуля

### 1. Калькулятор спринта (`/cms/planner`)

Планирование ёмкости по трекам (back / front / qa и др.):

- история velocity по трекам;
- headcount, отсутствия, рабочие дни, буфер %;
- рекомендуемый SP на трек;
- сохранение планов (`cms_sprint_plans`) и сравнение «план vs факт» в конце спринта.

**Права:** `cms.planner.view`

---

### 2. Отчёты месяца / релиза (`/cms/scope`)

Scope board — живой отчёт по команде за период. Данные подтягиваются из Jira по JQL.

#### Настройка доски

- **Команда и период** — привязка к `cms_teams`.
- **Ёмкость** — общий SP или раздельно `sp_dev_test` (Dev / Test).
- **Секции scope** — одна или несколько JQL-секций (planned / unplanned).
- **Очереди** — `todo_jql` (на груминг), `test_jql` (на тест).
- **Релизы** — дополнительные JQL (`release_queries`) с комментариями к каждому.
- **Эпик плана** (`plan_epic_key`) — Jira-issue, куда экспортируется AI-сводка (ADF-комментарий).

#### Шаблоны отчёта

| Шаблон | Команды | Особенности |
|---|---|---|
| **monthly** | большинство команд | несколько секций scope, месячная ёмкость |
| **release** | `igaming-ios`, `igaming-android` | один блок «Текущий релиз» + доп. release queries |

#### Обновление из Jira

Кнопка **«Обновить из Jira»** вызывает `POST /cms/scope-boards/{id}/refresh` и строит snapshot:

- ёмкость vs plan / unplan, буфер SP;
- intake status (`ok` / `warning` / `stop`);
- scope creep, гистограмма статусов;
- нагрузка по ролям (front / back / qa) — горизонты **active** и **sprint**;
- priority queues с ручной сортировкой и комментариями в Jira (ADF);
- open questions, top items, floating TODO, activity feed.

#### Блоки UI (порядок настраивается drag-and-drop)

Сводка, capacity dashboard, role workload charts, plan insights, **AI-панель**, секции отчёта, priority queues, activity feed, таблицы snapshot, режим презентации, печать в PDF.

#### Scope AI

После refresh можно запустить **AI-анализ** (`POST …/analyze`):

- health badge: «Под контролем» / «Есть риски» / «Критично»;
- что хорошо / что плохо / критичные пункты;
- blockers, focus, рекомендации по буферу;
- учитывает метрики доски и нагрузку по ролям.

**Экспорт в Jira:** если задан `plan_epic_key`, после анализа summary сохраняется как ADF-комментарий к эпику. Статусы в UI:

| Бейдж | Значение |
|---|---|
| «Отправляем в Jira…» | экспорт в процессе |
| «Сохранено в Jira» | комментарий записан или обновлён |
| «Ошибка Jira» | сбой записи (наведите для текста ошибки) |
| «Jira: ожидание» | эпик задан, экспорт ещё не завершён |

Повторный экспорт пропускается, если hash summary не изменился.

**Права:** `cms.planner.view` (тот же permission, что и калькулятор)

---

### 3. Сессии Planning Poker (`/cms/sessions`)

#### Менеджер (cockpit)

- Создание сессии, выбор команды и режима оценки (flat / split по трекам).
- Импорт задач из Jira (JQL или ключи) или ручной ввод.
- Генерация invite-ссылки `/s/{token}` для участников.
- Управление фазами: start → vote → reveal → final estimate → next task.
- **AI summary** по задаче (Claude) с опциональной записью ADF-комментария в Jira.
- Запись Story Points обратно в Jira (общее поле или split: dev / front / qa).
- Экспорт отчёта: CSV, Markdown.
- Telegram-алерт при завершении сессии.

#### Участник (`/s/{token}`)

- Вход: email + роль (backend / frontend / qa / manager).
- Голосование картами: 1, 2, 3, 5, 8, 13, 21.
- Live-обновление через WebSocket.

**Права CMS:** `cms.sessions.view`, управление сессией — `app.sessions.manage`

---

### 4. Ретроспективы (`/cms/retro`)

#### Фасилитатор

- Создание retro, invite `/r/{token}`.
- Секции с таймером, анонимные карточки.
- Фаза голосования (`votes_per_person`), группировка, action items.
- Финализация и **AI-анализ** закрытой ретро.

#### Участник (`/r/{token}`)

- Добавление карточек, голосование, live через WebSocket.

**Права:** просмотр `cms.retro.view`, управление `cms.retro.manage`, AI `cms.retro.analyze`

---

## CMS — остальные разделы

| Раздел | Путь | Описание |
|---|---|---|
| Сводка | `/cms` | KPI по четырём модулям: калькулятор, отчёты scope, сессии, ретро; участники и активные invite-ссылки. Фильтр по команде для супер-админа |
| Участники | `/cms/users` | Справочник web-участников |
| Журнал действий | `/cms/events` | Аудит CMS |
| Доступы | `/cms/access` | Админы, роли, permissions, команды |

### RBAC

16 permissions, ключевые:

- `cms.overview.view`, `cms.sessions.view`, `cms.planner.view`
- `cms.retro.view`, `cms.retro.manage`, `cms.retro.analyze`
- `cms.access.view`, `cms.access.manage`
- `app.sessions.manage`, `cms.tasks.manage`
- `cms.web_participants.delete`

Навигация CMS фильтруется по permissions principal'а. Порядок вкладок хранится в `cms_pages`.

### Списки по командам

В разделах **калькулятор**, **сессии**, **ретро**, **отчёты** (`/cms/planner`, `/cms/sessions`, `/cms/retro`, `/cms/scope`) записи привязаны к команде.

Если в списке видны **две и более команд** (и фильтр не зафиксирован на одной), UI автоматически делит экран на секции:

1. заголовок команды (алфавитный порядок, locale `ru`);
2. таблица / карточки только этой команды (внутри — по дате обновления, новые сверху).

При **одной команде** — плоский список, как раньше, с `TeamBadge` в строке. Супер-админ может сузить список фильтром «Команда».

Реализация: `web/src/features/cms/components/teamGrouping.ts`, `TeamGroupedSections.tsx`, `GroupedDataTableList`.

---

## Публичные страницы

| URL | Назначение |
|---|---|
| `/` | Landing — хаб четырёх модулей |
| `/demo` | Демо-сессия без Jira (`JIRA_DEMO_FALLBACK`) |
| `/403` | Отказ по IP allowlist (VPN) |

---

## Уведомления

- **Telegram при завершении сессии** — ссылка на отчёт (нужны `TELEGRAM_*` в runtime `.env`).
- **Telegram при CI/deploy** — старт и результат pipeline по каждому сервису.

---

## Типичные сценарии

### Подготовка к планированию спринта

1. Открыть `/cms/planner`, заполнить ёмкость и velocity.
2. Создать сессию в `/cms/sessions`, импортировать backlog из Jira.
3. Раздать invite, провести голосование, записать SP в Jira.

### Еженедельный scope review

1. Открыть доску команды в `/cms/scope`.
2. **Обновить из Jira** → проверить intake status и буфер.
3. Запустить **AI-анализ** → при необходимости summary уйдёт в эпик плана.
4. Отсортировать priority queues, оставить комментарии в Jira.

### Ретро в конце спринта

1. Создать retro, раздать `/r/{token}`.
2. Пройти секции, проголосовать, сформировать action items.
3. Finalize → AI-анализ для итогового summary.

---

## Ограничения и зависимости

- Сайт доступен только с IP из `SITE_ALLOWED_IPS` (корпоративный VPN).
- Jira-интеграция требует service account и корректных custom field ID.
- AI-функции (summary задачи, scope AI, retro analyze) требуют `ANTHROPIC_API_KEY`.
- Scope refresh и AI имеют rate limits (см. [TECHNICAL.md](./TECHNICAL.md)).

---

## Связанная документация

- [TECHNICAL.md](./TECHNICAL.md) — архитектура, API, env vars, тесты
- [../infra/deploy/PRODUCTION.md](../infra/deploy/PRODUCTION.md) — деплой и эксплуатация
