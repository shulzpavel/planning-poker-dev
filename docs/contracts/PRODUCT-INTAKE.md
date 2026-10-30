# Product intake release contract

Authenticated CMS users see the intake dashboard only when the server grants its owner capability. Every data/AI request independently verifies the configured owner plus planner permission. Unconfigured/disabled sources fail closed. Other users, including other superusers, cannot fetch the owner's data.

GET /cms/dashboards/intake?days=7|30|90 returns the existing chart snapshot plus source metadata, freshness and server-calculated historical speed. On the first load a 202 response indicates background refresh. On later loads an expired snapshot is served explicitly stale while an automatic refresh runs. Failed/incomplete Jira reads never replace the last successful snapshot.

GET /cms/dashboards/intake/analysis?days=7|30|90 returns an analysis matching that snapshot; 202 means generation/review is running. Cache keys include source settings, snapshot, period, model and prompt version. Invalid model output has no template fallback. Keys and evidence references must belong to the chart context. Credentials and model calls remain server-side.

Jira-service POST /intake/source loads all matching work items and every changelog page with bounded concurrency, normalizes existing status timeline logic, and returns a completeness-checked source. Truncation, failed pages and malformed items fail the refresh. JQL, stage statuses, source field, timezone and owner come from server settings, not frontend constants.

The web page lives under the normal authenticated CMS shell at /cms/dashboards/intake. Only real implemented stages are rendered. Existing prototype middleware, snapshots, fake header and development route are excluded from the release. The UI preserves the approved design and renders server-derived metrics; no analytics business logic remains in the browser.

## Configuration and rollout

Set INTAKE_DASHBOARD_ENABLED=true only after all linked service changes are deployed.
The default is false. Set INTAKE_DASHBOARD_JQL to the complete population of
initiatives (for example, project = EXAMPLE AND issuetype = Epic ORDER BY key).
Do not restrict this JQL to the current intake statuses or a recent updated
window: tasks that left intake are needed for historical metrics.
INTAKE_DASHBOARD_OWNER defaults to the existing CMS_USERNAME; another owner must
be an existing account with cms.planner.view. Other superusers have no implicit
access. No database migration or recurring user setup is needed.

INTAKE_DASHBOARD_SOURCE_FIELD is the Jira custom field ID for initiative source;
empty means unattributed and never falls back to reporter or assignee. Title,
stage display name, IANA timezone, intake/information/deferred/rejected status
names are deployment settings. Status lists are JSON arrays; empty environment
values use the documented business defaults. Seven days is an analytic review
threshold, not an agreed SLA. Only the implemented intake stage is released.

Snapshots refresh automatically on demand every 300 seconds (configurable
60–3600), and the browser checks at least once a minute while open. The last
good source is retained in Redis for seven days and explicitly marked stale
when refresh fails. No incomplete response is published as a successful zero
snapshot. Source refresh has a 600-second job limit; locks last 660 seconds and
are fenced before publish/release. Errors back off for 60 seconds. All workers
are cancelled and awaited on shutdown. A server restart can require a fresh
load if Redis was cleared. This feature does not run periodic work while the
page is closed.

Intake AI uses INTAKE_AI_MODEL (default claude-sonnet-4-6) with the existing
ANTHROPIC_API_KEY. One generation and one fact review run server-side. Cache
keys include configuration, model, prompt version and snapshot content. Locks
prevent duplicate work across tabs/processes. A malformed response may have
one correction attempt. No key or Jira export is sent to the browser bundle.
The model sees computed aggregate facts and an explicit sample of at most ten
contributing task records per chart; it must not treat the sample as a full
cohort. Evidence/keys are validated against that chart before display. Model
review is not a guarantee of every semantic claim, so supporting facts remain
visible.

## Historical metrics

First-ever intake entries count as new demand; returns do not inflate that
cohort. First-decision time includes the entire first intake visit, including
waiting for information. Open visits are excluded. Median and arithmetic mean
use timestamps, not rounded display durations. Weekly cohorts use the date of
first decision in the configured timezone, with gaps for empty weeks. The
comparison baseline is contiguous and has the same elapsed duration as the
selected window, including the partial current day. Missing previous decisions
produce an unavailable comparison, not a zero duration. Current queue data is
independent of the historical period selector.

## Release validation

- Authentication, other-user/superuser denial, disabled configuration and period validation.
- Full search/changelog pagination, failed pages, limit handling and timestamp consistency.
- Deduplication, stale-source retention, expired-worker fencing and model evidence rejection.
- Server speed calculations, DST buckets and empty cohorts.
- CMS owner navigation and desktop/mobile drilldowns, including asynchronous initial load.
- Standard frontend build and unit suite; backend pytest suites and Compose validation.

Deployment/merge order: Jira adapter, voting-service, web, then deployment
configuration. Keep the feature disabled through the transition; enable it
after an authenticated staging smoke test with the intended owner.
