# Logical deletion of Autonomia agents

## Decision and scope

The agent DELETE endpoint and the abandoned-draft reaper archive agents instead
of destroying them. The public DELETE contract remains HTTP 204. Account-level
authorization and system-agent exclusion remain unchanged.

Archived agents have `deleted_at` and `deleted_by_id`, are paused and disabled,
and are excluded explicitly from user-facing and runtime lookups. No default
scope hides historical associations from recovery queries. This is not a
restore UI and cannot recover agents physically deleted before this change.

Instructions, avatar, sources/files, knowledge, tools, specialists, versions,
events and build threads remain attached. Linked inboxes are released and their
Autonomia AgentInbox rows archived. Only the live native AgentBotInbox routing
join is removed: retaining it would prevent the core's has_one bot relationship
from selecting a replacement bot. The sender AgentBot remains, preserving past
messages' identity. A partial unique index still enforces one live agent per
inbox while allowing historical links.

## Audit and concurrency

Deletion, link archival and audit creation use one transaction and an agent row
lock. An audit persistence failure rolls back deletion. Repeated service calls
do not replace the original author/time or create duplicate audits. Connecting
an inbox and applying a builder result acquire the same agent lock.

`audits` records the agent, associated account, actor, deletion timestamp,
request ID and reason. `stale_draft` with a null actor identifies automated
cleanup. A structured `autonomia.agent.soft_deleted` log is emitted only after
commit. Neither the log nor audit contains instruction, knowledge, tool headers,
API keys or configuration payloads. `deleted_by_id` nullifies on user removal;
the audit metadata preserves the original actor ID.

Pending knowledge/builder jobs do not start on archived agents. Existing reply
and async-tool delivery gates re-resolve only live inbox links. A deleted agent
cannot be tested, edited or reconnected through the ordinary API.

## Validation

- Added focused request/service coverage for preservation, durable audit,
  rollback, idempotence, account isolation, disabled runtime, pending jobs and
  reconnecting a replacement agent.
- Updated the reaper tests to require archival, not physical deletion.
- `git diff --check`: passed.
- Worktree Husky hooks cannot run because `.husky/_/husky.sh` is absent;
  commit/push use a per-command empty hooks path, without changing Git settings.
- Ruby 2.6 syntax check passes for changed/new Ruby files except the existing
  endless-method syntax in the insurance builder, which requires modern Ruby.
- Full RSpec, RuboCop and a database-generated schema dump cannot run locally:
  Ruby 3.4.4/rbenv, the project bundle and local PostgreSQL are unavailable.
  The schema is synchronized with the migration; verify it with Rails 7.2 and
  PostgreSQL in CI/development before merging. This is not a generated-dump
  claim. Focused specs are included in the existing full-suite PR workflow.

No production database, Redis, EC2 or Rails runtime was accessed for this change.
No manual deployment was executed. Deployment and the migration must go through
the approved workflow. Keep the deletion markers and audit during an application
rollback; older code does not know how to hide archived agents. Do not reverse
the migration after archival/replacement links exist without a reviewed data
recovery plan (the old unique index cannot represent multiple historical links).

## PR 1063 check and conflict correction

- Integrated main `16a91fb1dd`, including the campaign scheduling fixture fix
  (`04378cbeae`); the fixed fixture now schedules relative to the test clock.
- Resolved the sole conflict at the schema version header, retaining the agent
  migration version and main's Meta connection/ad preview columns and index.
- Updated external-agent lifecycle request expectations to preserve the agent,
  archived link and historical bot, remove only native live routing, and
  attribute the persistent audit to the administrator.
- Corrected Ruby layout offenses and separated the locked builder write from
  generation eligibility checks. FAQ resolution excludes an archived historical
  agent before extraction, with regression coverage.
- Added a CI database-only migration roundtrip spec. It compares Rails-generated
  schema dumps before/after down/up within a rolled-back transaction, including
  FK and partial index reconstruction. It is not permission to reverse an
  archive containing replacement links in production.
- Local full Rails/RuboCop execution remains unavailable; the PR workflows must
  validate the updated head. No CI success is inferred from syntax checking.
