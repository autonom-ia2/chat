# Email campaign hygiene — #436 / PR0

Tenant-scoped suppression history, temporary quarantine and asynchronous recipient preflight. No reputation policy, reports endpoint, UI, SMTP probing, mailbox verification, address repair or automatic resume. Import and send eligibility never perform DNS.

## Configuration

| Variable | Default | Contract |
| --- | --- | --- |
| `EMAIL_CAMPAIGN_HYGIENE_MODE` | `shadow` | `shadow`, `warning`, `enforce` |
| `EMAIL_CAMPAIGN_HYGIENE_DNS_ENABLED` | `false` | Explicit `true` or `false`, independently of mode |
| `EMAIL_CAMPAIGN_SOFT_BOUNCE_THRESHOLD` | `3` | Integer 1–100 distinct events |
| `EMAIL_CAMPAIGN_SOFT_BOUNCE_WINDOW_DAYS` | `7` | Integer 1–365 |
| `EMAIL_CAMPAIGN_QUARANTINE_HOURS` | `72` | Integer 1–8760 |

`HygieneConfig.new(env = ENV)` rejects invalid configuration. Shadow records findings and permits delivery under syntax and current suppression rules. Warning also exposes warnings. Neither changes recipient status from preflight findings. Enforce allows only fresh `valid` DNS outcomes. Deterministic `invalid` and explicit `review` results exclude the recipient from this campaign (`status=suppressed`); unknown/timeout/DNS-disabled/unchecked recipients remain pending and hold admission with `hygiene_validation_required`. DNS=false therefore cannot clear an ordinary list in enforce. Configuration changes require the parent's rollout approval.

## Mixed-version suppression contract

`email_suppressions` remains the original permanent-positive table, with its existing unique `(account_id, lower(email))` index. The migration does **not alter this table**, backfill it, delete records, or install triggers. No observation, inactive state or expiring quarantine is inserted there.

`email_suppression_states` holds all new observations and decisions. It has account, normalized email, active=false by default, reason, source, expires_at, first_seen_at, last_seen_at, occurrences=0, origin_campaign_id and created_at. A unique `(account_id, email)` index plus a normalization check constraint protects the key. `email_suppression_events.email_suppression_state_id` references this new state, not the legacy table. The audit replay index is `(account_id, email_suppression_state_id, event_key)`.

```ruby
registry = EmailCampaigns::SuppressionRegistry.new(account: account, email: email, campaign: campaign)
registry.block!(reason: 'unsubscribe', source: 'link', event_key: 'unsubscribe:123')
registry.record!(reason: 'temporary_failure', source: 'ses', event_key: 'ses:message-id:bounce',
                 occurred_at: timestamp, metadata: { 'reason_code' => 'mailbox_full' })
```

Both return `Result(suppression:, event:, duplicate:)`; **suppression is now an EmailSuppressionState**. Optional campaign must belong to account. `config:` accepts an injected HygieneConfig. `occurred_at:` defaults to current time and `metadata:` to `{}`. Event keys are stable, nonblank, at most 200 characters and unique per tenant/address. Source is required.

`block!` accepts provider_suppression/hard_bounce/manual/complaint/unsubscribe. `record!` also accepts temporary_failure/unknown_bounce. DNS/format findings never go through the registry. First state insertion uses ON CONFLICT, followed by a row lock. Event append, occurrence count, state decision and **strong legacy mirror** commit atomically. The mirror uses ON CONFLICT too and never removes or weakens an existing legacy positive. Priority for known reasons is unsubscribe > complaint > manual > hard_bounce > provider_suppression > temporary_failure; unknown legacy reasons remain authoritative.

Old unsubscribe `find_or_create_by!` now finds no placeholder after a new transient event and creates a permanent row normally. Old complaint/hard-bounce creation likewise has no collision with new transient state. If an old writer later creates a permanent positive while new state is inactive/temporary, that positive wins on all new reads, even after quarantine expiry and old/new rollback cycles. Old code does not enforce new temporary quarantine or preflight; permanent protection remains available through its original table.

Three distinct temporary events in the active seven-day window create/extend quarantine to **the newest qualifying event's occurred_at + 72 hours**, retaining any later existing expiry. The window is `[processing time - 7 days, processing time]`; future and older records do not qualify. Arrival order never chooses expiry: events at T, T-1d and T-6d processed at T produce the same T+72h expiry in chronological or reverse order. Both block immediately and stop blocking at exactly T+72h. SES future timestamps are capped at processing time. Replay never inflates occurrences. Expiry only affects the new temporary state; it cannot release any legacy positive, change recipient history, retry delivery or resume a campaign.

A replay of the same event_key can carry corrected historical evidence. A **strictly stronger strong reason** promotes the state and legacy positive atomically; unknown_bounce → hard_bounce and provider_suppression → hard_bounce are supported, while hard_bounce → provider_suppression is a duplicate. The original event is never updated/deleted. Each accepted promotion appends action=`correction`, key=`correction:<original event ID>:<reason>` (bounded below the 200-character limit even for a 200-character original key), the original occurred_at, the correction source/metadata and `metadata.corrects_event_id`. The state occurrence count includes this additional audit entry; correction entries never count as temporary failures. Equal/weaker replays, including after an earlier correction, append nothing and return duplicate=true. Further strictly stronger corrections are permitted once per reason. Unsubscribe > complaint > manual > hard_bounce protection and unknown legacy positives remain authoritative, including protection from independent event keys. Corrections do not release, resend or rewrite delivery history. PR442 backfill can use the original durable key after rebasing onto this registry; this PR runs no backfill.

PR438 unsubscribe and SNS writers acquire locks in **Account → recipient → suppression state/legacy row** order. This is compatible with a PR439 worker holding Account → campaign → recipient during blue/green overlap: the old web writer waits on Account before owning recipient, so the suppression-state Account FK cannot close a recipient→Account deadlock cycle. Counter refresh happens after those writer locks are released. No network/DNS/provider work occurs under these locks and no PR439 reputation class is needed. The generic HTTP 200 unsubscribe response is unchanged; PostgreSQL concurrency regressions assert persisted opt-out/state/legacy audit as well as the response, since a generic success alone could conceal rollback.

The internal `release!(source:, event_key:, authorization:, occurred_at:)` requires a nonblank reference **and permits only a manual state with no legacy row**. It rejects consent, spam, provider suppression, permanent failure, temporary state and every mirrored/legacy positive, including manual legacy rows. A string is never proof of resubscription. PR0 provides no release path for registry-created strong blocks; verified resubscribe is out of scope. Rejected release rolls back its audit insertion and counts. The method is not exposed by any controller/job.

### Read APIs for send/import/reports

- `EmailSuppression.suppressed?(account, email)` checks current legacy presence OR active new state.
- `EmailSuppression.suppressed_set_for(account)` returns normalized emails from that same union.
- `EmailSuppression.blocking_reasons_for(account, emails)` returns `{ normalized_email => reason_code }` for blocking addresses only, in two batch queries. Pass the current report page's emails or a bounded eligibility batch. Legacy reason wins over state; unknown legacy reasons map to `legacy_suppression`. Known codes: hard_bounce, manual, complaint, unsubscribe, provider_suppression, temporary_failure. No per-recipient query is needed for a report page.

Normalization preserves plus tags/dots and only trims/downcases. All lookups are account-scoped. Do not use legacy rows alone for new report/send eligibility, or state alone to infer that a recipient was released. Existing report fixtures creating temporary legacy rows must move to EmailSuppressionState; parent owns those files.

Audit events are immutable through the model (`readonly?` after insert), account-validated, and keep origin campaign ID, event key, source/reason/action, event time, first/last occurrence times and metadata. State aggregates distinct count/times. Origin IDs survive campaign deletion. No backfill is required. Raw SQL can bypass model audit integrity; this is not a tamper-proof external ledger.

## Import and bounded rejection codes

The importer keeps required `name,email` CSV headers, the existing parser, original source row numbers, a 50,000-row limit and atomic batches of 500 inserts. Entirely blank rows are ignored. Counts imported + duplicates + invalid + suppressed reconcile with total. Recipients, issues, counters and async completion commit together. There is no DNS in import.

`RecipientImporter.new(campaign, file, filename:, import: nil).perform` retains its existing result fields and adds `preflight: { status: 'pending', unchecked:, issues: }`. Import must belong to campaign. `EmailCampaignImportIssue` retains the original address (capped at 320), row number, bounded reason code and optional suggestion. Use `for_account(account)` or an authorized campaign association for reports. `export_attributes` escapes spreadsheet formulas.

Import issue codes: `blank_email`, `invalid_email`, **`invalid_recipient`**, `duplicate`, `suppressed`. A valid email rejected for another model field uses invalid_recipient, never a raw validator message or invalid_email. Recipient name is capped at 255 characters by model validation so a long name is recorded/reconciled as an issue. The required name header remains unchanged. Parent API/UI integration must support invalid_recipient and legacy_suppression; this worker does not edit reports or translations.

## Preflight enqueue and lease contract

```ruby
# Call after committing import, from maintenance, or from an authorized campaign endpoint.
EmailCampaigns::RecipientPreflightJob.enqueue(campaign.id)
# User explicitly requests revalidation of pending rows, including local-only findings:
EmailCampaigns::RecipientPreflightJob.enqueue(campaign.id, recheck: true)
```

Returns true for a newly scheduled pass, false for disabled/ineligible/no-due-work or an already live chain. A recheck during a live chain coalesces into that pass; it does not reset in-flight recipients. The controller should report an already-running pass and allow a later explicit recheck. `perform_later(campaign_id, token, cursor)` is an internal continuation API, not the UI enqueue API. Direct `perform_now(campaign_id)` can start/claim a pass but external scheduling should always use enqueue.

Four new campaign columns implement a durable five-minute lease: `preflight_lease_token`, `preflight_lease_expires_at`, `preflight_cursor` (default 0), `preflight_ceiling` (default 0). Acquisition serializes on the campaign row; queued tokens are consumed/rotated before work, so duplicate executions cannot start another chain. Each continuation gets a new token. Expired chains resume the persisted cursor/ceiling. A new or explicit pass starts at zero and captures the maximum recipient ID. Concurrent additions beyond the ceiling are discovered by the next maintenance pass.

Each job reads at most 100 rows, resolves at most 10 unique domains and yields once a monotonic ten-second work budget has elapsed. One already-started domain can consume up to three two-second DNS calls, so network work is bounded to roughly sixteen seconds per job, excluding local database/cache latency. The first row can progress even if the worker was stalled before iteration. Domain results are reused within the batch even with a NullStore/TTL zero. Cursor advances after every handled row; zero-TTL results cannot loop within the same pass.

DNS is outside database transactions and row locks; DNS-enabled perform rejects an already open transaction before creating a resolver. Writes compare pending status, previous checked timestamp and the current unexpired lease token. Stale holders cannot overwrite recipient evidence or another pass's summary. There is **one full status aggregation when the pass completes**, under the short campaign lock, never one per 100 rows. The summary is a snapshot, not an eligibility guarantee.

In enforce, the same fenced compare-and-set writes the preflight evidence and changes a deterministic `invalid` or explicit `review` recipient to `suppressed` atomically. This is **campaign-local exclusion, not permanent quarantine or tenant suppression**: no EmailSuppression, EmailSuppressionState or suppression event is created from DNS/typo findings. The original email, preflight_status, reason, suggestion and check timestamps remain auditable. No address is autocorrected. A user may correct the address and import it as a new pending row; after fresh valid preflight, ready peers can proceed while the original remains excluded. An explicit enforce recheck also handles invalid/review rows still pending from shadow/warning. Unknown, timeout, dns_disabled and unchecked are never excluded this way. Already claimed/sent/canceled rows and stale lease responses cannot receive this transition. Excluded rows remain excluded across mode changes and are not reset by pending-only rechecks.

Presentation integration must classify campaign-local exclusions from their retained `preflight_status/reason/suggestion` as invalid/review, rather than infer a permanent tenant block from `status=suppressed`. Actual tenant suppression remains independently authoritative. The report/presenter implementation lives in the parent integration worktree and is outside this PR0 change; its generic suppressed-to-protected classification must be aligned there.

The import after-update-commit callback uses enqueue. Maintenance discovers unchecked recipients, due external outcomes when DNS=true, and expired leases (including a crash after the last recipient write but before summary). An enqueue failure leaves the durable lease recoverable after expiry. No lock spans DNS. Dispatched recipients, terminal campaigns and active imports are excluded.

Maintenance isolates `ActiveRecord::RecordInvalid` for each campaign, including a draft DirectInbox campaign whose sender inbox was deleted. It logs JSON with only `event=email_campaign_preflight_enqueue_failed`, `campaign_id` and `error_class`; other campaigns continue. Existing import recovery and file retention run in an ensure path after preflight scheduling, including in shadow/DNS=false. Database/connection failures are not swallowed: housekeeping is attempted and the job still fails. An invalid campaign remains pending operator repair; this does not bypass its validations or disable shadow preflight.

Local-only outcomes (`dns_disabled`, provider_typo, unsupported_local_part, invalid_email, idn_requires_ascii_domain) have **no expiry**. Maintenance only requeues unchecked recipients when DNS=false. Enabling DNS also selects existing dns_disabled rows and expired external DNS outcomes. Pure typo/identity findings require explicit recheck; changing shadow/warning/enforce alone does not repeat identical DNS work. There is no periodic 50k-row churn in default shadow/DNS=false.

Recipient fields remain preflight_status (unchecked/valid/invalid/review/unknown), reason_code, suggestion, checked_at, valid_until. `PreflightDecision.new(config:).call(recipient)` returns allowed/mode/status/reason_code/suggestion/warning. `campaign_allowed?` and `unresolved` perform eligibility queries without DNS. Revalidation never clears manual/tenant/provider pauses, enqueues delivery, or resumes a campaign.

`unresolved` selects pending preflight candidates, so campaign-local suppressed invalid/review rows do not hold admission or finalization. `campaign_allowed?` checks the remaining candidates in batches of at most 500 through `EmailSuppression.blocking_reasons_for`. Currently blocked addresses are also excluded from the enforce hold, using the same tenant-scoped legacy/new-state union and expiry rules as delivery. An opt-out after import therefore allows fresh valid peers to proceed; the existing delivery claim/dispatch gates still prevent sending to the blocked address. Expired quarantine and inactive observations do not exempt eligible unresolved recipients. Unknown/DNS-disabled/unchecked and expired valid evidence still hold pending recipients. Previously pending invalid/review rows hold until enforce preflight/recheck excludes them. Active imports return false in every mode. These reads never reset persisted protection, resume campaigns or load the entire account's suppression set for each row.

## DNS transport and evidence

`DomainValidator.new(resolver:, cache:, clock:).call(domain)` returns status/reason_code/valid_until. Resolver responds to `call(domain, :MX | :A | :AAAA)` with status/records/ttl. Cache accepts read/write or Hash and contains domains only.

MX indicates a route, not mailbox existence. Exactly `0 .` is invalid/null_mx. Mixed/nonzero root MX is unknown/mixed_null_mx. Successful empty MX (NODATA) falls back to A then AAAA. A valid address route suffices; definitive absence of all routes is invalid. NXDOMAIN is invalid. Timeout and resolver errors remain unknown.

`Dns::MailRouteResolver.new(timeout: 2, resolver: Resolver)` accepts a positive deadline up to two seconds and an injected resolver implementing `.open { |dns| ... }`. Its stdlib Resolver accepts an injected nameserver config. One `Timeout.timeout` surrounds **DNS only**, including resolver open, UDP, TCP fallback connect/write and partial frame read. Resolv's open/fetch_resource ensure blocks close resolver/requesters; timeout maps to timeout → unknown/dns_timeout. Offline tests use real fetch_resource/TCP framing, a socket pair with incomplete length/body, and a fake UDP truncated response, with no external packets.

The adapter uses one nameserver and absolute names. Its observed config distinguishes NXDOMAIN from NODATA before stdlib consumes errors. SERVFAIL/REFUSED map conservatively to resolver_error. TTL is capped at one hour; unknown at five minutes. NXDOMAIN negative packet TTL is unavailable on this path, so TTL=0. No external dependencies or SMTP are introduced. Recheck stdlib transport tests on Ruby upgrades.

Curated gmial.com/gmail.con/hotmial.com produce suggestions only. Business domains, role addresses and disposable-address categories are not blacklisted by resemblance. Identity is never silently repaired. Non-ASCII local parts are invalid; Unicode domains require reviewed ASCII/Punycode. Already encoded domains use ordinary DNS.

## Delivery and SES

BounceClassifier separates the delivery outcome from the reason for preventing future sends. The following mapping applies to SES permanent bounce subtypes:

| SES bounceSubType | classification / reason_code | Protection | AWS bounce reputation meaning |
| --- | --- | --- | --- |
| General, NoEmail | permanent / permanent_failure | hard_bounce | Permanent failure; NoEmail means SES could not extract the recipient address from the bounce, not a nonexistent mailbox |
| Suppressed | permanent / provider_suppression | provider_suppression | Global SES suppression **does count** toward the AWS bounce rate |
| OnAccountSuppressionList | unknown / provider_suppression | provider_suppression | Account suppression, nonattempt; does not count toward bounce reputation |
| OnTenantSuppressionList | unknown / provider_suppression | provider_suppression | Tenant suppression, nonattempt; does not count toward bounce reputation |
| EmailValidationSuppressed | unknown / provider_suppression | provider_suppression | Provider prevention; not evidence of an attempted hard bounce |
| UnsubscribedRecipient | unknown / unsubscribe | unsubscribe | Opt-out, nonattempt; no sender reputation impact |

No subtype alone produces mailbox_not_found. Unknown here describes the delivery classification; a named provider prevention still produces a definite local block. Provider suppression activates a **nonexpiring tenant/address block**, mirrored into the legacy permanent-positive table in the same transaction. It survives temporary quarantine expiry, shadow mode, and mixed-version reads. It does not claim an invalid mailbox, call provider APIs, remove SES restrictions, or create a release/resend path. Existing opt-out/complaint/manual/hard-bounce protection retains priority. Historical observational provider rows are not backfilled by this change.

SNS processing serializes each recipient/type before metrics and registry writes; replay is counted once. It keeps the original Bounce payload even for provider prevention or opt-out. UnsubscribedRecipient records the existing unsubscribe protection, creates an unsubscribe event once when transitioning, and updates status/timestamps under the recipient lock without unrelated legacy-field validation. Bounce/delivery never overwrites unsubscribe, and bounce never overwrites complaint. Link unsubscribe token validation is unchanged.

Integration boundary for the parent: raw Bounce history and legacy bounced_count are not the AWS reputation numerator. Suppressed shares reason_code=provider_suppression with nonattempt events but has classification=permanent. Do not exclude every provider_suppression from reputation or count every such reason as provider-prevented. UnsubscribedRecipient must be excluded as opt-out. Reports/reputation SQL and UI alignment are owned by the parent/other agents and were not changed in this closure. Subtype facts were supplied by the parent after checking official AWS notification, global suppression and Firehose event documentation; this worker made no external requests.

SES and DirectInbox use DeliveryClaim before claiming and again after rendering, immediately before dispatch. Current union lookup wins over a stale preloaded Set. Previously dispatched history is unchanged. No database lock spans provider calls. Blocks committed after provider dispatch begins cannot recall that message.

Only explicit HTTP 429 rejection is retried. Timeout/connection loss/5xx can follow acceptance and never return to pending. Failed post-send persistence retains the sent claim. Finalization refuses pending recipients, active imports and unreceipted sent claims. A local claim demonstrably not dispatched can return to pending after a pause; ambiguous claims require operator review, never blind resend.

## Migration, rollback and validation boundary

Migration `20260916120000` remains undeployed and was corrected before merge. The foreign keys from `email_campaign_import_issues` to both campaign and import use **`ON DELETE CASCADE`** so an older web process that does not know the new association can still delete a campaign/import during blue-green or code rollback. The second migration retains the due-validity index and adds a concurrent partial `(email_campaign_id, id)` index for pending/unchecked rows, keeping default maintenance proportional to unfinished work. No data backfill, data deletion, trigger or modification of legacy suppression schema is included. `down` refuses destruction of new audit/state.

The compatibility gate used a disposable PostgreSQL database loaded from the exact `main` schema (`cd30dba0c9…`), then ran the #443 migrations through `20260916123000`. Both real constraints reported `ON DELETE CASCADE`. The exact old `main` request/controller stack, authenticated with its normal token flow and without the new Ruby association, then deleted a campaign containing a new import-issue row with HTTP **204**; campaign, import and issue all reached zero rows. No production database or destructive down migration was used.

Apply additive schema before new code. Keep shadow/DNS=false during the mixed-version portion of the single blue-green. Permanent legacy positives remain authoritative in old and new versions. Behavioral rollback is shadow/DNS=false with schema/state/audit retained; drain/suspend jobs unknown to the old reader before code rollback. Code rollback retains permanent positives but loses temporary-state enforcement until reupgrade. No automatic resume or resend occurs.

### Retention and existing recipients

Recipient import keeps the existing ApplicationRecord 255-character string limit; this feature does not introduce a new name policy. A rejection unrelated to the address is classified as `invalid_recipient`, never as proof of an invalid email. Signed opt-out transitions update only status/timestamps under a lock, so unrelated invalid fields on a legacy record cannot roll back permanent protection.

Rejected `raw_address` evidence containing NUL or invalid UTF-8 is represented with Ruby byte escapes (for example, literal `\x00` and `\xFF`), then capped at 320 characters. The invalid row remains counted with `invalid_email`; valid peers stay in the same atomic import batch. Invalid encoding is detected before address trimming/normalization, and blank-row filtering preserves malformed evidence even when the name is blank. This changes evidence only, not valid address identity or normalization. CSV formula escaping remains in `export_attributes`/`CsvSanitizer`. Offline simulated persistence tests and new Rails regressions are recorded in `docs/audit/436-pr0-review-fixes.md`; PostgreSQL execution remains the parent's responsibility.

Observation states belong to the account and are removed by the database only when an authorized existing account-deletion flow removes that account. Append-only audit rows retain numeric logical account/state references without blocking deletion; they do not retain a copied recipient address. Normal campaign operations cannot delete or rewrite audit history. Legacy permanent suppressions keep their previous retention behavior. Code rollback and mode changes never delete suppression/audit data.
