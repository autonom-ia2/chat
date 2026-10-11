# BUILD MANIFEST — SLA Inteligente (SLA v2)

> AUTHORITATIVE. Nine implementation agents code in parallel on DISJOINT files. Every contract below is final — do not deviate, do not invent
> alternative names/paths/keys. PRD: `docs/crm_sla_v2_prd.md`. Fork root: `/root/docker-stacks/build/chatwoot-campaign-v4.14.1`.
> Conventions: Ruby rubocop 150 cols, compact `module/class` defs; Vue 3 `<script setup>` Composition API, Tailwind `n-*` tokens only,
> components-next, `i-lucide-*` icons, ZERO bare strings (only i18n keys from §10). i18n parity pt_BR ↔ en 1:1 mandatory.
> HARD RULE: everything additive; native SLA byte-identical when new toggles are OFF.

---

## 0. Discovered facts (verified in the codebase — trust these, do not re-derive)

| Fact | Value |
|---|---|
| Rails migration superclass | `ActiveRecord::Migration[7.1]` (see `db/migrate/20260610120000_create_crm_saved_views.rb`) |
| Latest migration timestamp | `20260610120000` — new migrations use `202606111000xx` |
| Pipeline-inbox link model | `Crm::PipelineInbox` (`app/models/crm/pipeline_inbox.rb`, table `crm_pipeline_inboxes`, account assoc `Current.account.crm_pipeline_inboxes`) |
| CRM base controller | `Api::V1::Accounts::Crm::BaseController` (`app/controllers/api/v1/accounts/crm/base_controller.rb`) — `before_action :ensure_crm_enabled` |
| CRM enabled check (backend) | `Crm::Config.enabled?` (env `CRM_KANBAN_ENABLED`) |
| CRM AI enabled check (backend) | `Crm::Ai::Config.enabled?` (`Crm::Config.enabled? && ENV['CRM_AI_ENABLED']`) — in `app/services/crm/ai/config.rb` |
| Cheapest AI model constant | `Crm::Ai::Config::MODEL_CLASSIFY` = `'gpt-5.4-mini'` — AiBreachGuard uses THIS constant |
| ResponsesClient contract | `Crm::Ai::ResponsesClient.new(credential:).create(model:, instructions:, input:, schema:, reasoning_effort: 'low')` returns `{ text:, usage:, response_id: }`; parse with `JSON.parse(response[:text])`; raises `Crm::Ai::ResponsesClient::Error` |
| Credential resolver | `Crm::Ai::CredentialResolver.new(account:).resolve` → hash or nil |
| Account feature check (backend) | `account.feature_enabled?('sla')` (pattern: `enterprise/app/presenters/enterprise/conversations/event_data_presenter.rb`) |
| Account feature check (frontend) | getter `accounts/isFeatureEnabledonAccount(accountId, 'sla')`; flag constant `FEATURE_FLAGS.SLA = 'sla'` in `app/javascript/dashboard/featureFlags.js` |
| CRM frontend gate | `window.globalConfig?.CRM_KANBAN_ENABLED === 'true'` (`ensureCrmEnabled` in `crm.routes.js`); sidebar uses `globalConfig.value?.crmKanbanEnabled === true` |
| CRM permission constants (FE) | `app/javascript/dashboard/constants/permissions.js`: `CRM_ADMIN_PERMISSION = 'crm_admin'` |
| CRM Pundit pattern | OSS `app/policies/crm/integration_token_policy.rb` (admin-only) + EE mirror `enterprise/app/policies/enterprise/crm/integration_token_policy.rb` using `include CrmPermissions` + `crm_permission?('crm_admin')`; OSS file ends with `Crm::XPolicy.prepend_mod_with('Crm::XPolicy')` |
| CRM jbuilder view pattern | `app/views/api/v1/accounts/crm/pipeline_inboxes/{index,show,_pipeline_inbox}.json.jbuilder`; controller `create` does `render :show, status: :created` |
| SLA jbuilder views | `enterprise/app/views/api/v1/accounts/sla_policies/{index,show,create,update}.json.jbuilder`, ALL delegate to partial `enterprise/app/views/api/v1/models/_sla_policy.json.jbuilder` (only the partial needs new fields) |
| SLA policy Pundit | `enterprise/app/policies/sla_policy_policy.rb` (unchanged — admin create/update/destroy, agent index/show) |
| AppliedSla push payload | `applied_sla.push_event_data` → `{ id, sla_id, sla_status, created_at(int), updated_at(int), sla_description, sla_name, sla_first_response_time_threshold, sla_next_response_time_threshold, sla_only_during_business_hours, sla_resolution_time_threshold }` — exactly what `SLACardLabel`/`evaluateSLAStatus` expects |
| `evaluateSLAStatus` chat needs | `chat.first_reply_created_at`, `chat.waiting_since` (epoch s or nil), `chat.status` ('open' string) |
| CRM job queues | event-driven jobs `queue_as :low` (`Crm::SyncConversationCardJob`); cron jobs `queue_as :scheduled_jobs`. `Crm::SlaAutoApplyJob` uses `:low` |
| Listener helper | `BaseListener#extract_conversation_and_account(event)` (`app/listeners/base_listener.rb:4`); event `conversation.created` exists (`lib/events/types.rb:17`), listeners implement `def conversation_created(event)` |
| Timezone validation pattern (BE) | `TZInfo::Timezone.get(...)` rescue `TZInfo::InvalidTimezoneIdentifier` (inbox uses `TZInfo::Timezone.all_identifiers`) |
| Timezone options helper (FE) | `import { timeZoneOptions } from 'dashboard/routes/dashboard/settings/inbox/helpers/businessHour'` (`timeZoneOptions()` → `[{label, value}]`; value = IANA id) |
| Sidebar i18n file | `app/javascript/dashboard/i18n/locale/en/settings.json` + `app/javascript/dashboard/i18n/locale/pt_BR/settings.json`, section `"SIDEBAR"` (holds `CRM`, `CRM_KANBAN`, `CRM_DASHBOARD`, `SLA`) |
| crm.json structure | top-level keys `CRM_KANBAN`, `CRM_INTEGRATION_TOKENS` in `app/javascript/dashboard/i18n/locale/{en,pt_BR}/crm.json` — new top-level `CRM_SLA` section goes here |
| sla store registration | `app/javascript/dashboard/store/index.js` line 48 `import sla from './modules/sla';` + line 115 `sla,` — already registered, NO registration change needed |
| sla store gaps | `store/modules/sla.js` has get/create/delete only. `EDIT_SLA` mutation-type already exists (`mutation-types.js:366`). `api/sla.js` extends `ApiClient` → inherited `update(id, obj)` works, NO api change needed. Store needs a new `update` action + `EDIT_SLA` mutation + `isUpdating` flag |
| settings/sla importers | ONLY `app/javascript/dashboard/routes/dashboard/settings/settings.routes.js` (line 22 import, line 63 spread). Route name `sla_list` referenced ONLY by `Sidebar.vue:851`. No other importer exists — verified by grep |
| Message model gotcha | `default_scope` orders ASC — always `.reorder(created_at: :desc)` for recent messages |
| Conversation → JID | ~~`conversation.contact_inbox.source_id`~~ — **errado para caixa WAHA** (lá o `source_id` é uuid). O chat id fica em `contact.custom_attributes` (`waha_whatsapp_chat_id` / `waha_whatsapp_jid`); `source_id` é só fallback. Ver PRD §3.2 e #1276. |
| EE conversation concern | `enterprise/app/models/enterprise/concerns/conversation.rb` — `has_one :applied_sla`; AppliedSla auto-created in `around_save` when `sla_policy_id` changes (so auto-apply only needs `conversation.update!(sla_policy_id:)`) |
| ActionService add_sla | `enterprise/app/services/enterprise/action_service.rb` — `@account`, `@conversation` ivars available |

---

## 1. FILE OWNERSHIP (disjoint — a file appears in exactly ONE package)

| Pkg | Scope | Files (N=new, E=edit, D=delete) |
|---|---|---|
| **A** | db + models | N `db/migrate/20260611100000_create_crm_service_schedules.rb` · N `db/migrate/20260611100100_add_sla_v2_fields_to_sla_policies.rb` · N `db/migrate/20260611100200_add_metadata_to_applied_slas.rb` · N `app/models/crm/service_schedule.rb` · E `enterprise/app/models/sla_policy.rb` |
| **B** | engine | E `enterprise/app/services/sla/evaluate_applied_sla_service.rb` · N `enterprise/app/services/sla/business_time_calculator.rb` · N `enterprise/app/services/sla/schedule_resolver.rb` |
| **C** | groups + auto-apply | N `app/services/crm/whatsapp_group_detector.rb` · E `enterprise/app/services/enterprise/action_service.rb` · N `app/jobs/crm/sla_auto_apply_job.rb` · E `app/listeners/crm/conversation_observer_listener.rb` |
| **D** | ai-guard | N `enterprise/app/services/sla/ai_breach_guard.rb` |
| **E** | api | E `enterprise/app/controllers/api/v1/accounts/sla_policies_controller.rb` · E `enterprise/app/views/api/v1/models/_sla_policy.json.jbuilder` · E `config/routes.rb` · N `app/controllers/api/v1/accounts/crm/service_schedules_controller.rb` · N `app/views/api/v1/accounts/crm/service_schedules/index.json.jbuilder` · N `.../show.json.jbuilder` · N `.../_service_schedule.json.jbuilder` · N `app/policies/crm/service_schedule_policy.rb` · N `enterprise/app/policies/enterprise/crm/service_schedule_policy.rb` |
| **F** | crm-sla-page | E `app/javascript/dashboard/routes/dashboard/crm/crm.routes.js` · N `app/javascript/dashboard/routes/dashboard/crm/pages/CrmSlaPage.vue` · N `app/javascript/dashboard/routes/dashboard/crm/components/sla/CrmSlaPolicyList.vue` · N `.../sla/CrmSlaPolicyDialog.vue` · N `.../sla/CrmSlaTimeInput.vue` · E `app/javascript/dashboard/store/modules/sla.js` |
| **G** | schedule-editor + agent-dialog | N `app/javascript/dashboard/routes/dashboard/crm/components/sla/CrmScheduleEditor.vue` · N `.../sla/CrmInboxScheduleList.vue` · N `app/javascript/dashboard/api/crmServiceSchedules.js` · E `app/javascript/dashboard/routes/dashboard/settings/agents/EditAgent.vue` |
| **H** | badge | E `app/services/crm/cards/payload_builder.rb` · E `app/javascript/dashboard/routes/dashboard/crm/components/CrmKanbanCard.vue` · E `app/javascript/dashboard/routes/dashboard/crm/components/list/CrmCardsTable.vue` · E `app/javascript/dashboard/routes/dashboard/crm/components/list/cardColumns.js` |
| **I** | i18n | E `app/javascript/dashboard/i18n/locale/en/crm.json` · E `app/javascript/dashboard/i18n/locale/pt_BR/crm.json` · E `app/javascript/dashboard/i18n/locale/en/settings.json` · E `app/javascript/dashboard/i18n/locale/pt_BR/settings.json` |
| **J** | integration (sidebar + settings removal) | E `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` · E `app/javascript/dashboard/routes/dashboard/settings/settings.routes.js` · D `app/javascript/dashboard/routes/dashboard/settings/sla/` (entire directory: `Index.vue`, `AddSLA.vue`, `SlaForm.vue`, `SlaTimeInput.vue`, `SLAPaywallEnterprise.vue`, `sla.routes.js`, `validations.js`) |

Cross-package call sites are interface-only: B calls `Crm::WhatsappGroupDetector` (C) and `Sla::AiBreachGuard` (D) and `Crm::ServiceSchedule` (A) by the exact signatures below; F's page imports G's components by exact path/props. Locked decisions: AddAgent.vue is NOT touched (one schedule per user; calendar is edited after the agent exists, via EditAgent). `api/sla.js`, `applied_sla.rb`, `sla_event.rb`, `sla_policy_policy.rb`, all `enterprise/app/jobs/sla/*`, `WorkingHour`, and SLA reports (`sla_reports` route, `slaReports` store, `SIDEBAR.REPORTS_SLA`) are NOT touched by anyone.

---

## 2. Wave 1 — Fair business hours

### 2.1 Migration 1 — `db/migrate/20260611100000_create_crm_service_schedules.rb` (Pkg A)

```ruby
class CreateCrmServiceSchedules < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_service_schedules do |t|
      t.bigint :account_id, null: false, index: true
      t.string :owner_type, null: false
      t.bigint :owner_id, null: false
      t.string :timezone, null: false
      t.boolean :enabled, null: false, default: true
      t.jsonb :blocks, null: false, default: []
      t.timestamps
    end

    add_index :crm_service_schedules, [:account_id, :owner_type, :owner_id], unique: true, name: 'idx_crm_service_schedules_owner_unique'
    add_index :crm_service_schedules, [:owner_type, :owner_id]
  end
end
```

### 2.2 Migration 2 — `db/migrate/20260611100100_add_sla_v2_fields_to_sla_policies.rb` (Pkg A)

```ruby
class AddSlaV2FieldsToSlaPolicies < ActiveRecord::Migration[7.1]
  def change
    add_column :sla_policies, :exclude_groups, :boolean, null: false, default: true
    add_column :sla_policies, :ai_skip_natural_pause, :boolean, null: false, default: true
    add_column :sla_policies, :auto_apply, :jsonb, null: false, default: {}
  end
end
```

### 2.3 Migration 3 — `db/migrate/20260611100200_add_metadata_to_applied_slas.rb` (Pkg A)

```ruby
class AddMetadataToAppliedSlas < ActiveRecord::Migration[7.1]
  def change
    add_column :applied_slas, :metadata, :jsonb, null: false, default: {}
  end
end
```

### 2.4 Model — `app/models/crm/service_schedule.rb` (Pkg A)

```ruby
class Crm::ServiceSchedule < ApplicationRecord
  self.table_name = 'crm_service_schedules'

  OWNER_TYPES = %w[Inbox User].freeze

  belongs_to :account
  belongs_to :owner, polymorphic: true

  validates :timezone, presence: true
  validates :owner_type, inclusion: { in: OWNER_TYPES }
  validates :owner_id, uniqueness: { scope: [:account_id, :owner_type] }
  validate :timezone_must_be_valid
  validate :blocks_must_be_well_formed

  scope :enabled, -> { where(enabled: true) }

  def usable?
    enabled? && parsed_blocks.any?
  end

  # Sorted [start_minute, end_minute] pairs for a weekday (0=Sunday..6=Saturday).
  def blocks_for(wday)
    parsed_blocks.select { |block| block['day_of_week'] == wday }
                 .map { |block| [block['start_minute'], block['end_minute']] }
                 .sort_by(&:first)
  end

  private

  def parsed_blocks
    blocks.is_a?(Array) ? blocks : []
  end

  def timezone_must_be_valid
    TZInfo::Timezone.get(timezone.to_s)
  rescue TZInfo::InvalidTimezoneIdentifier
    errors.add(:timezone, 'is not a valid IANA timezone identifier')
  end

  def blocks_must_be_well_formed
    return errors.add(:blocks, 'must be an array') unless blocks.is_a?(Array)

    valid = blocks.all? do |block|
      block.is_a?(Hash) &&
        (0..6).cover?(block['day_of_week']) &&
        block['start_minute'].is_a?(Integer) && (0..1438).cover?(block['start_minute']) &&
        block['end_minute'].is_a?(Integer) && block['end_minute'] > block['start_minute'] && block['end_minute'] <= 1440
    end
    errors.add(:blocks, 'contains an invalid block') unless valid
  end
end
```

Note: jsonb hashes round-trip with STRING keys; the controller (§5.3) normalizes params to string-keyed integer-valued hashes before save.

### 2.5 SlaPolicy reader (Pkg A — edit `enterprise/app/models/sla_policy.rb`)

Add one public method (keep everything else byte-identical):

```ruby
  # Safe accessor for the jsonb auto_apply config. Shape:
  # { 'enabled' => bool, 'event' => 'conversation_created', 'inbox_ids' => [Integer], 'pipeline_ids' => [Integer] }
  def auto_apply_config
    config = auto_apply.is_a?(Hash) ? auto_apply : {}
    {
      'enabled' => ActiveModel::Type::Boolean.new.cast(config['enabled']) || false,
      'event' => config['event'].presence || 'conversation_created',
      'inbox_ids' => Array(config['inbox_ids']).map(&:to_i),
      'pipeline_ids' => Array(config['pipeline_ids']).map(&:to_i)
    }
  end
```

### 2.6 Service — `enterprise/app/services/sla/business_time_calculator.rb` (Pkg B)

```ruby
class Sla::BusinessTimeCalculator
  MAX_DAYS = 800

  def initialize(schedule:)
    @schedule = schedule
    @timezone = ActiveSupport::TimeZone[schedule.timezone] || ActiveSupport::TimeZone['UTC']
  end

  # Seconds of business time between +from+ and +to+, counting only seconds inside
  # the schedule blocks, walking day by day in the schedule timezone. DST-safe:
  # each day is re-anchored with beginning_of_day in the zone. Short-circuits once
  # the accumulated total reaches +limit+ (the SLA threshold).
  def elapsed_seconds(from, to, limit: nil)
    return 0 if from.blank? || to.blank? || from >= to

    from = from.in_time_zone(@timezone)
    to = to.in_time_zone(@timezone)
    total = 0
    day_start = from.beginning_of_day

    MAX_DAYS.times do
      break if day_start > to

      @schedule.blocks_for(day_start.wday).each do |start_minute, end_minute|
        overlap = [to, day_start + end_minute.minutes].min - [from, day_start + start_minute.minutes].max
        total += overlap if overlap.positive?
      end
      return total.round if limit.present? && total >= limit

      day_start = (day_start + 1.day).beginning_of_day
    end

    total.round
  end
end
```

### 2.7 Service — `enterprise/app/services/sla/schedule_resolver.rb` (Pkg B)

```ruby
class Sla::ScheduleResolver
  # Calendar precedence (LOCKED): CURRENT assigned agent at evaluation time,
  # else the conversation inbox, else nil (callers fall back to 24/7 wall clock).
  # Lookups are account-scoped.
  def self.for_conversation(conversation)
    if conversation.assignee_id.present?
      schedule = Crm::ServiceSchedule.find_by(account_id: conversation.account_id, owner_type: 'User', owner_id: conversation.assignee_id)
      return schedule if schedule&.usable?
    end

    schedule = Crm::ServiceSchedule.find_by(account_id: conversation.account_id, owner_type: 'Inbox', owner_id: conversation.inbox_id)
    schedule&.usable? ? schedule : nil
  end
end
```

### 2.8 Engine rewrite — `enterprise/app/services/sla/evaluate_applied_sla_service.rb` (Pkg B)

This file is rewritten ONCE by Pkg B and includes the Wave-2 group skip and Wave-3 AI hook (interfaces owned by C and D). Final file contract:

UNCHANGED (byte-identical): class header `class Sla::EvaluateAppliedSlaService` + `pattr_initialize [:applied_sla!]`, `perform`, `check_sla_thresholds`, `get_last_message_id`, `already_missed?`, `handle_hit_sla`, `create_sla_event`, all log lines.

REMOVED: `still_within_threshold?` (replaced; do not leave dead code).

CHANGED/NEW private methods (exact):

```ruby
  def check_first_response_time_threshold(applied_sla, conversation, sla_policy)
    return if skip_group_thresholds?(conversation, sla_policy)
    return if first_reply_was_within_threshold?(conversation, sla_policy)
    return unless threshold_breached?(conversation.created_at, sla_policy.first_response_time_threshold, sla_policy)

    handle_missed_sla(applied_sla, 'frt')
  end

  def first_reply_was_within_threshold?(conversation, sla_policy)
    conversation.first_reply_created_at.present? &&
      elapsed_seconds(conversation.created_at, conversation.first_reply_created_at, sla_policy) <= sla_policy.first_response_time_threshold.to_i
  end

  def check_next_response_time_threshold(applied_sla, conversation, sla_policy)
    return if skip_group_thresholds?(conversation, sla_policy)
    # still waiting for first reply, so covered under first response time threshold
    return if conversation.first_reply_created_at.blank?
    # Waiting on customer response, no need to check next response time threshold
    return if conversation.waiting_since.blank?
    return unless threshold_breached?(conversation.waiting_since, sla_policy.next_response_time_threshold, sla_policy)

    handle_missed_sla(applied_sla, 'nrt')
  end

  def check_resolution_time_threshold(applied_sla, conversation, sla_policy)
    return if skip_group_thresholds?(conversation, sla_policy)
    return if conversation.resolved?
    return unless threshold_breached?(conversation.created_at, sla_policy.resolution_time_threshold, sla_policy)

    handle_missed_sla(applied_sla, 'rt')
  end

  # Wall-clock path is arithmetically identical to the legacy epoch compare
  # (now >= start + threshold), so behavior with only_during_business_hours=false
  # or with no usable schedule is byte-identical to native.
  def threshold_breached?(started_at, threshold_seconds, sla_policy)
    elapsed_seconds(started_at, Time.zone.now, sla_policy, limit: threshold_seconds.to_i) >= threshold_seconds.to_i
  end

  def elapsed_seconds(from, to, sla_policy, limit: nil)
    return to.to_i - from.to_i unless business_time?(sla_policy)

    Sla::BusinessTimeCalculator.new(schedule: resolved_schedule).elapsed_seconds(from, to, limit: limit)
  end

  def business_time?(sla_policy)
    sla_policy.only_during_business_hours? && resolved_schedule.present?
  end

  # Memoized per perform run (nil is a valid resolution — hence defined? guard).
  # only_during_business_hours? short-circuits in business_time? so the resolver
  # never runs a query for 24/7 policies.
  def resolved_schedule
    @resolved_schedule = Sla::ScheduleResolver.for_conversation(applied_sla.conversation) unless defined?(@resolved_schedule)
    @resolved_schedule
  end

  # Defensive Wave-2 skip: group conversations stop accruing breaches but the
  # resolved hit/missed path (handle_hit_sla via perform) stays untouched.
  def skip_group_thresholds?(conversation, sla_policy)
    sla_policy.exclude_groups? && Crm::WhatsappGroupDetector.group_conversation?(conversation)
  end

  def handle_missed_sla(applied_sla, type, meta = {})
    meta = { message_id: get_last_message_id(applied_sla.conversation) } if type == 'nrt'
    return if already_missed?(applied_sla, type, meta)
    # Wave-3 AI breach guard: runs ONLY at the exact moment a breach would be
    # recorded (after the already_missed? cache, before creating the SlaEvent).
    return if Sla::AiBreachGuard.new(applied_sla: applied_sla, breach_type: type).skip_breach?

    create_sla_event(applied_sla, type, meta)
    Rails.logger.warn "SLA #{type} missed for conversation #{applied_sla.conversation.id} " \
                      "in account #{applied_sla.account_id} " \
                      "for sla_policy #{applied_sla.sla_policy.id}"

    applied_sla.update!(sla_status: 'active_with_misses') if applied_sla.sla_status != 'active_with_misses'
  end
```

---

## 3. Wave 2 — Groups

### 3.1 `app/services/crm/whatsapp_group_detector.rb` (Pkg C)

```ruby
module Crm
  class WhatsappGroupDetector
    GROUP_SUFFIX = '@g.us'.freeze
    BROADCAST_FRAGMENT = '@broadcast'.freeze
    NEWSLETTER_SUFFIX = '@newsletter'.freeze

    # Non-1:1 WhatsApp JIDs (WAHA/Evolution): groups end with @g.us, broadcasts
    # contain @broadcast (incl. status@broadcast), channels end with @newsletter.
    def self.group_conversation?(conversation)
      source_id = conversation&.contact_inbox&.source_id.to_s.downcase
      return false if source_id.blank?

      source_id.end_with?(GROUP_SUFFIX, NEWSLETTER_SUFFIX) || source_id.include?(BROADCAST_FRAGMENT)
    end
  end
end
```

### 3.2 Guard in `Enterprise::ActionService#add_sla` (Pkg C — edit `enterprise/app/services/enterprise/action_service.rb`)

Insert ONE line after `return if @conversation.sla_policy.present?`:

```ruby
    return if sla_policy.exclude_groups? && Crm::WhatsappGroupDetector.group_conversation?(@conversation)
```

(The same guard inside the auto-apply job is in §4.1. The engine-side defensive skip is `skip_group_thresholds?` in §2.8, owned by B.)

---

## 4. Wave 4 backend — Auto-apply + endpoints

### 4.1 `app/jobs/crm/sla_auto_apply_job.rb` (Pkg C)

```ruby
class Crm::SlaAutoApplyJob < ApplicationJob
  queue_as :low

  def perform(conversation_id)
    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.blank?

    account = conversation.account
    return unless account.feature_enabled?('sla')
    return if conversation.sla_policy_id.present?

    policy = account.sla_policies.order(:id).detect { |sla_policy| applies?(sla_policy, conversation) }
    return if policy.blank?

    Rails.logger.info "SLA:: Auto-applying SLA #{policy.id} to conversation: #{conversation.id}"
    conversation.update!(sla_policy_id: policy.id)
  end

  private

  # LOCKED decision 4: policy applies when auto-apply is enabled for
  # conversation_created AND (both lists empty = all) OR the conversation inbox
  # is selected OR the inbox belongs to a selected pipeline (Crm::PipelineInbox).
  def applies?(sla_policy, conversation)
    config = sla_policy.auto_apply_config
    return false unless config['enabled'] && config['event'] == 'conversation_created'
    return false if sla_policy.exclude_groups? && Crm::WhatsappGroupDetector.group_conversation?(conversation)

    inbox_ids = config['inbox_ids']
    pipeline_ids = config['pipeline_ids']
    return true if inbox_ids.empty? && pipeline_ids.empty?
    return true if inbox_ids.include?(conversation.inbox_id)

    pipeline_ids.any? && Crm::PipelineInbox.exists?(account_id: conversation.account_id, pipeline_id: pipeline_ids, inbox_id: conversation.inbox_id)
  end
end
```

(`order(:id).detect` = lowest-id match wins. The EE conversation concern creates the AppliedSla automatically on `update!`.)

### 4.2 Listener hook (Pkg C — edit `app/listeners/crm/conversation_observer_listener.rb`)

Add a public method between `message_created` and `assignee_changed`:

```ruby
  # SLA auto-apply v1 (gatilho "conversa criada"): hand off to a job so listener
  # stays fast; all gating (feature flag, policy match, groups) lives in the job.
  def conversation_created(event)
    return unless Crm::Config.enabled?

    conversation, = extract_conversation_and_account(event)
    return if conversation&.id.blank?

    Crm::SlaAutoApplyJob.perform_later(conversation.id)
  end
```

### 4.3 SlaPolicies controller params + jbuilder (Pkg E)

`enterprise/app/controllers/api/v1/accounts/sla_policies_controller.rb` — replace `permitted_params` body only:

```ruby
  def permitted_params
    params.require(:sla_policy).permit(:name, :description, :first_response_time_threshold, :next_response_time_threshold,
                                       :resolution_time_threshold, :only_during_business_hours, :exclude_groups, :ai_skip_natural_pause,
                                       auto_apply: [:enabled, :event, { inbox_ids: [], pipeline_ids: [] }])
  end
```

`enterprise/app/views/api/v1/models/_sla_policy.json.jbuilder` — append:

```ruby
json.exclude_groups sla_policy.exclude_groups
json.ai_skip_natural_pause sla_policy.ai_skip_natural_pause
json.auto_apply sla_policy.auto_apply_config
```

### 4.4 Routes (Pkg E — edit `config/routes.rb`)

Inside the existing `namespace :crm do` block (after `resources :follow_ups ... end`), add:

```ruby
            resources :service_schedules, only: [:index, :create, :update, :destroy]
```

Route names: `api_v1_account_crm_service_schedules` (index/create), `api_v1_account_crm_service_schedule` (update/destroy). URL: `/api/v1/accounts/:account_id/crm/service_schedules(/:id)`.

### 4.5 Controller — `app/controllers/api/v1/accounts/crm/service_schedules_controller.rb` (Pkg E)

```ruby
class Api::V1::Accounts::Crm::ServiceSchedulesController < Api::V1::Accounts::Crm::BaseController
  before_action :fetch_schedule, only: [:update, :destroy]

  def index
    authorize ::Crm::ServiceSchedule
    @service_schedules = policy_scope(::Crm::ServiceSchedule).order(:owner_type, :owner_id)
  end

  # Upsert per owner: one schedule per [account, owner] (LOCKED decision 5).
  def create
    owner = fetch_owner
    @service_schedule = ::Crm::ServiceSchedule.find_or_initialize_by(account_id: Current.account.id, owner: owner)
    @service_schedule.assign_attributes(schedule_attributes)
    authorize @service_schedule
    @service_schedule.save!
    render :show, status: :created
  end

  def update
    @service_schedule.update!(schedule_attributes)
    render :show
  end

  def destroy
    @service_schedule.destroy!
    head :no_content
  end

  private

  def fetch_schedule
    @service_schedule = ::Crm::ServiceSchedule.find_by!(account_id: Current.account.id, id: params[:id])
    authorize @service_schedule
  end

  # Owner is ALWAYS resolved inside Current.account (never a global find).
  def fetch_owner
    case permitted_params[:owner_type]
    when 'Inbox' then Current.account.inboxes.find(permitted_params[:owner_id])
    when 'User' then Current.account.users.find(permitted_params[:owner_id])
    else raise ActiveRecord::RecordNotFound
    end
  end

  def schedule_attributes
    {
      timezone: permitted_params[:timezone],
      enabled: permitted_params.key?(:enabled) ? permitted_params[:enabled] : true,
      blocks: normalized_blocks
    }
  end

  # jsonb stores string keys; coerce minutes to Integer so model validation holds.
  def normalized_blocks
    Array(permitted_params[:blocks]).map do |block|
      { 'day_of_week' => block[:day_of_week].to_i, 'start_minute' => block[:start_minute].to_i, 'end_minute' => block[:end_minute].to_i }
    end
  end

  def permitted_params
    params.require(:service_schedule).permit(:owner_type, :owner_id, :timezone, :enabled, blocks: [:day_of_week, :start_minute, :end_minute])
  end
end
```

### 4.6 Jbuilder views (Pkg E)

`app/views/api/v1/accounts/crm/service_schedules/_service_schedule.json.jbuilder`:

```ruby
json.id service_schedule.id
json.owner_type service_schedule.owner_type
json.owner_id service_schedule.owner_id
json.timezone service_schedule.timezone
json.enabled service_schedule.enabled
json.blocks service_schedule.blocks
```

`index.json.jbuilder`:

```ruby
json.payload do
  json.array! @service_schedules do |service_schedule|
    json.partial! 'api/v1/accounts/crm/service_schedules/service_schedule', service_schedule: service_schedule
  end
end
```

`show.json.jbuilder`:

```ruby
json.payload do
  json.partial! 'api/v1/accounts/crm/service_schedules/service_schedule', service_schedule: @service_schedule
end
```

### 4.7 Pundit (Pkg E) — pattern copied from `app/policies/crm/integration_token_policy.rb` + `enterprise/app/policies/enterprise/crm/integration_token_policy.rb`

`app/policies/crm/service_schedule_policy.rb`:

```ruby
class Crm::ServiceSchedulePolicy < ApplicationPolicy
  # SLA service calendars are account configuration: administrators only.
  # The EE overlay (Enterprise::Crm::ServiceSchedulePolicy) relaxes this to crm_admin.
  def index?
    administrator?
  end

  def create?
    administrator?
  end

  def update?
    administrator? && record.account_id == account.id
  end

  def destroy?
    update?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(account_id: account.id)
    end
  end

  private

  def administrator?
    account_user&.administrator?
  end
end

Crm::ServiceSchedulePolicy.prepend_mod_with('Crm::ServiceSchedulePolicy')
```

`enterprise/app/policies/enterprise/crm/service_schedule_policy.rb`:

```ruby
module Enterprise::Crm::ServiceSchedulePolicy
  include CrmPermissions

  def index?
    crm_permission?('crm_admin')
  end

  def create?
    crm_permission?('crm_admin')
  end

  def update?
    crm_permission?('crm_admin') && record.account_id == account.id
  end

  def destroy?
    update?
  end
end
```

---

## 5. Wave 3 — AI breach guard

### 5.1 `enterprise/app/services/sla/ai_breach_guard.rb` (Pkg D)

```ruby
class Sla::AiBreachGuard
  CONFIDENCE_THRESHOLD = 0.6 # LOCKED decision 3: fixed internal constant
  TRANSCRIPT_LIMIT = 20
  CONTENT_LIMIT = 500

  # OPENAI STRICT SCHEMA: every property listed in required, additionalProperties false.
  SCHEMA = {
    name: 'sla_breach_guard',
    schema: {
      type: 'object',
      properties: {
        customer_waiting: { type: 'boolean', description: 'true se há um cliente realmente esperando uma resposta NOSSA agora.' },
        reason: { type: 'string', maxLength: 300, description: 'Justificativa curta baseada APENAS na transcrição. Não invente fatos.' },
        confidence: { type: 'number', minimum: 0, maximum: 1 }
      },
      required: %w[customer_waiting reason confidence],
      additionalProperties: false
    }
  }.freeze

  INSTRUCTIONS = <<~PROMPT.freeze
    Você audita SLAs de atendimento no Brasil. Leia a transcrição (cliente x agente) e decida:
    há um cliente realmente esperando uma resposta NOSSA agora?
    Responda customer_waiting=false quando a pausa é saudável (relacionamento contínuo sem pendência),
    quando a bola está com o cliente (última pendência é dele), ou quando a conversa foi encerrada/resolvida.
    Responda customer_waiting=true quando existe pergunta, pedido ou pendência do cliente sem resposta nossa.
    Baseie-se SOMENTE na transcrição; não invente fatos. Em caso de dúvida, customer_waiting=true com confidence baixa.
    Responda apenas com JSON válido no schema solicitado.
  PROMPT

  def initialize(applied_sla:, breach_type:)
    @applied_sla = applied_sla
    @breach_type = breach_type.to_s
  end

  # true => suppress the breach (no SlaEvent). Fail-open: any error counts the breach.
  def skip_breach?
    return false unless @applied_sla.sla_policy.ai_skip_natural_pause?
    return false unless Crm::Ai::Config.enabled?
    return false unless @applied_sla.account.feature_enabled?('sla')

    credential = Crm::Ai::CredentialResolver.new(account: @applied_sla.account).resolve
    return false if credential.blank?
    return false if last_message_id.blank?

    decision = cached_decision || fresh_decision(credential)
    return false if decision.blank?

    decision['customer_waiting'] == false && decision['confidence'].to_f >= CONFIDENCE_THRESHOLD
  rescue StandardError => e
    Rails.logger.warn "SLA:: AiBreachGuard failed for applied_sla #{@applied_sla.id}: #{e.message}"
    false
  end

  private

  def conversation
    @applied_sla.conversation
  end

  # Reuse the cached decision while no new relevant message arrived (cost guard).
  def cached_decision
    cached = (@applied_sla.metadata || {})['ai_pause']
    return unless cached.is_a?(Hash)

    cached if cached['source_message_id'].present? && cached['source_message_id'] == last_message_id
  end

  def fresh_decision(credential)
    response = Crm::Ai::ResponsesClient.new(credential: credential).create(
      model: Crm::Ai::Config::MODEL_CLASSIFY,
      instructions: INSTRUCTIONS,
      input: transcript,
      schema: SCHEMA,
      reasoning_effort: 'low'
    )
    decision = JSON.parse(response[:text])
    persist_cache(decision)
    decision
  end

  def persist_cache(decision)
    @applied_sla.update!(
      metadata: (@applied_sla.metadata || {}).merge(
        'ai_pause' => {
          'customer_waiting' => decision['customer_waiting'],
          'reason' => decision['reason'],
          'confidence' => decision['confidence'],
          'source_message_id' => last_message_id,
          'breach_type' => @breach_type,
          'decided_at' => Time.zone.now.iso8601
        }
      )
    )
  end

  # Message has a default_scope ordered ASC — always .reorder for recent messages.
  def last_message_id
    @last_message_id ||= relevant_messages.reorder(created_at: :desc).first&.id
  end

  def relevant_messages
    conversation.messages.where(message_type: [:incoming, :outgoing], private: false)
  end

  def transcript
    lines = relevant_messages.reorder(created_at: :desc).limit(TRANSCRIPT_LIMIT).to_a.reverse.map do |message|
      role = message.incoming? ? 'cliente' : 'agente'
      "[#{role}] #{message.content.to_s.truncate(CONTENT_LIMIT)}"
    end
    "Tipo de prazo em quebra: #{@breach_type.upcase}\nTranscrição (mais antiga -> mais recente):\n#{lines.join("\n")}"
  end
end
```

Engine hook: already wired by Pkg B in §2.8 `handle_missed_sla` (after `already_missed?`, before `create_sla_event`). Pkg D creates ONLY this file.

---

## 6. Wave 5 — Badge (Pkg H)

### 6.1 `app/services/crm/cards/payload_builder.rb` — replace `conversation_payload` and add one private helper

```ruby
  def conversation_payload
    return if primary_conversation.blank?
    return unless primary_conversation_visible?

    payload = {
      id: primary_conversation.id,
      display_id: primary_conversation.display_id,
      inbox_id: primary_conversation.inbox_id,
      status: primary_conversation.status,
      assignee_id: primary_conversation.assignee_id,
      team_id: primary_conversation.team_id,
      first_reply_created_at: primary_conversation.first_reply_created_at&.to_i,
      waiting_since: primary_conversation.waiting_since&.to_i
    }
    applied_sla = applied_sla_payload
    payload[:applied_sla] = applied_sla if applied_sla.present?
    payload
  end

  # SLA badge data (Kanban/List). Gated on the account 'sla' feature; uses the
  # native push_event_data shape that SLACardLabel/evaluateSLAStatus consume.
  def applied_sla_payload
    return unless @card.account.feature_enabled?('sla')

    primary_conversation.applied_sla&.push_event_data
  end
```

### 6.2 `CrmKanbanCard.vue` — script setup additions

```js
import SLACardLabel from 'dashboard/components-next/Conversation/Sla/SLACardLabel.vue';

// SLACardLabel expects the conversation-list "chat" shape; card.conversation
// already carries applied_sla + epoch fields from the payload builder.
const slaChat = computed(() => {
  const conversation = props.card?.conversation;
  if (!conversation?.applied_sla) return null;
  return {
    applied_sla: conversation.applied_sla,
    first_reply_created_at: conversation.first_reply_created_at,
    waiting_since: conversation.waiting_since,
    status: conversation.status,
  };
});
```

Template: FIRST element inside the existing "Signal pills" row (`<div class="mt-2.5 flex flex-wrap items-center gap-1.5">`), before the channel `CrmCardPill`:

```vue
      <SLACardLabel v-if="slaChat" :chat="slaChat" />
```

### 6.3 `cardColumns.js` — dedicated SLA column

- Add `'sla'` to `DEFAULT_COLUMN_ORDER` immediately AFTER `'status'`.
- Add `sla: 110` to the `COLUMN_SIZES` map.
- Add column def right after the `status` column def:

```js
    {
      id: 'sla',
      accessorFn: row => row?.conversation?.applied_sla?.id ?? '',
      header: L('SLA'),
      enableSorting: false,
      size: COLUMN_SIZES.sla,
      meta: { kind: 'sla' },
    },
```

Header key: `CRM_KANBAN.LIST.COLUMNS.SLA` (the `L()` helper namespace — provided by Pkg I).

### 6.4 `CrmCardsTable.vue`

- `import SLACardLabel from 'dashboard/components-next/Conversation/Sla/SLACardLabel.vue';`
- Script helper:

```js
const slaChatFor = card => {
  const conversation = card?.conversation;
  if (!conversation?.applied_sla) return null;
  return {
    applied_sla: conversation.applied_sla,
    first_reply_created_at: conversation.first_reply_created_at,
    waiting_since: conversation.waiting_since,
    status: conversation.status,
  };
};
```

- Template: in the `cellKind(cell.column)` chain (next to the existing `=== 'conversation'` branch) add:

```vue
            <template v-else-if="cellKind(cell.column) === 'sla'">
              <SLACardLabel
                v-if="slaChatFor(row.original)"
                :chat="slaChatFor(row.original)"
              />
              <span v-else class="text-n-slate-10">—</span>
            </template>
```

---

## 7. Wave 4 frontend — CRM SLA page

### 7.1 Route (Pkg F — edit `crm.routes.js`)

Add import `import CrmSlaPage from './pages/CrmSlaPage.vue';` and a route entry AFTER `crm_dashboard_index`:

```js
  {
    path: frontendURL('accounts/:accountId/crm/sla'),
    name: 'crm_sla_index',
    meta: adminMeta, // existing const: ['administrator', CRM_ADMIN_PERMISSION]
    beforeEnter: ensureCrmEnabled,
    component: CrmSlaPage,
  },
```

### 7.2 Store (Pkg F — edit `store/modules/sla.js`)

- `uiFlags` initial state gains `isUpdating: false`.
- New action (between `create` and `delete`):

```js
  update: async function update({ commit }, { id, ...slaObj }) {
    commit(types.SET_SLA_UI_FLAG, { isUpdating: true });
    try {
      const response = await SlaAPI.update(id, slaObj);
      commit(types.EDIT_SLA, response.data.payload);
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit(types.SET_SLA_UI_FLAG, { isUpdating: false });
    }
  },
```

- New mutation: `[types.EDIT_SLA]: MutationHelpers.update,` (`EDIT_SLA` already exists in `mutation-types.js`).
- `api/sla.js` is NOT changed (ApiClient base provides `update`).

### 7.3 API module (Pkg G) — `app/javascript/dashboard/api/crmServiceSchedules.js`

```js
import ApiClient from './ApiClient';

// CRUD for /api/v1/accounts/:accountId/crm/service_schedules.
// Inherited: get(), create(data), update(id, data), delete(id).
// Payload wrapper: { service_schedule: { owner_type, owner_id, timezone, enabled, blocks } }
// where blocks = [{ day_of_week: 0..6, start_minute, end_minute }].
class CrmServiceSchedulesAPI extends ApiClient {
  constructor() {
    super('crm/service_schedules', { accountScoped: true });
  }
}

export default new CrmServiceSchedulesAPI();
```

Call signatures (no store module — components own local state):
- `CrmServiceSchedulesAPI.get()` → `{ data: { payload: [schedule] } }`
- `CrmServiceSchedulesAPI.create({ service_schedule })` → upsert per owner → `{ data: { payload: schedule } }`
- `CrmServiceSchedulesAPI.update(id, { service_schedule })`
- `CrmServiceSchedulesAPI.delete(id)`

### 7.4 Page — `pages/CrmSlaPage.vue` (Pkg F)

`<script setup>`; identity reference: `CrmDashboardPage.vue` (header + sections, Tailwind `n-*`). Composition:

- Header: `CRM_SLA.HEADER.TITLE` + `CRM_SLA.HEADER.DESCRIPTION`.
- Feature paywall: `const isSlaFeatureEnabled = computed(() => store.getters['accounts/isFeatureEnabledonAccount'](accountId.value, 'sla'));` (`useMapGetter('getCurrentAccountId')` for accountId, `FEATURE_FLAGS.SLA` from `dashboard/featureFlags`). When false render ONLY a paywall block (`i-lucide-lock` icon, `CRM_SLA.PAYWALL.TITLE`, `CRM_SLA.PAYWALL.DESCRIPTION`) — no API calls.
- Section "Políticas": renders `<CrmSlaPolicyList />` (import `../components/sla/CrmSlaPolicyList.vue`).
- Section "Calendários": renders `<CrmInboxScheduleList />` (import `../components/sla/CrmInboxScheduleList.vue` — built by Pkg G).
- `onMounted` (only when feature enabled): `store.dispatch('sla/get')`, `store.dispatch('inboxes/get')`, and fetch pipelines via existing `CrmKanbanAPI.getPipelines()` (`dashboard/api/crmKanban`) passing the result down to the dialog for the pipeline multiselect.

### 7.5 `components/sla/CrmSlaPolicyList.vue` (Pkg F)

Props: `pipelines: { type: Array, default: () => [] }`. Uses store getters `sla/getSLA`, `sla/getUIFlags`, store `inboxes/getInboxes`.
- Table (components-next `BaseTable/BaseTableRow/BaseTableCell` like settings list): columns `CRM_SLA.POLICIES.TABLE.{NAME,BUSINESS_HOURS,FRT,NRT,RT,AUTO_APPLY,ACTIONS}`; thresholds rendered with `convertSecondsToTimeUnit` from `@chatwoot/utils`; business-hours / auto-apply cells show `CRM_SLA.POLICIES.BADGES.{ENABLED,DISABLED}`; row badges for `exclude_groups` (`CRM_SLA.POLICIES.BADGES.GROUPS_EXCLUDED`) and `ai_skip_natural_pause` (`CRM_SLA.POLICIES.BADGES.AI_GUARD`).
- "Add" Button (`i-lucide-plus`) label `CRM_SLA.POLICIES.ADD`; empty state `CRM_SLA.POLICIES.EMPTY`.
- Edit (`i-lucide-pencil`) opens `<CrmSlaPolicyDialog :policy="..." :pipelines="pipelines" />`; delete (`i-lucide-trash-2`) opens confirm dialog (`CRM_SLA.POLICIES.DELETE.*`) then `store.dispatch('sla/delete', id)` + `useAlert` with `CRM_SLA.POLICIES.API.DELETE_SUCCESS/DELETE_ERROR`.

### 7.6 `components/sla/CrmSlaPolicyDialog.vue` (Pkg F)

Props: `policy: { type: Object, default: null }` (null = create), `pipelines: Array`. Emits: `close`, `saved`. Native `<dialog>` or the components-next Dialog pattern used elsewhere in `crm/components` (follow `CrmPipelineDrawer.vue` dialog idiom). Fields:
- name (required, min 2 — error `CRM_SLA.POLICIES.DIALOG.NAME.REQUIRED_ERROR`), description.
- Three `<CrmSlaTimeInput>` rows for FRT/NRT/RT (labels `CRM_SLA.POLICIES.DIALOG.{FRT,NRT,RT}.LABEL`), converting to seconds on submit (`convertSecondsToTimeUnit` for hydrate; multiply by 60/3600/86400 on save — copy the math from the deleted `settings/sla/SlaForm.vue`).
- Toggles (components-next `switch/Switch.vue`): `only_during_business_hours` (`...BUSINESS_HOURS.LABEL/NOTE`), `exclude_groups` (`...EXCLUDE_GROUPS.LABEL/NOTE`), `ai_skip_natural_pause` (`...AI_SKIP.LABEL/NOTE`). Defaults for create: business_hours `false`, exclude_groups `true`, ai_skip `true`.
- Auto-apply block (`...AUTO_APPLY.TITLE`): enabled toggle (`...AUTO_APPLY.ENABLED_LABEL`, note `...AUTO_APPLY.NOTE`); when enabled show inbox multiselect (store `inboxes/getInboxes`, placeholder `...AUTO_APPLY.INBOXES_ALL`, label `...AUTO_APPLY.INBOXES_LABEL`) and pipeline multiselect (`pipelines` prop, label `...AUTO_APPLY.PIPELINES_LABEL`, placeholder `...AUTO_APPLY.PIPELINES_ALL`).
- Submit payload: `{ name, description, first_response_time_threshold, next_response_time_threshold, resolution_time_threshold, only_during_business_hours, exclude_groups, ai_skip_natural_pause, auto_apply: { enabled, event: 'conversation_created', inbox_ids, pipeline_ids } }` → `store.dispatch('sla/create', payload)` or `store.dispatch('sla/update', { id, ...payload })`; alert `CRM_SLA.POLICIES.API.SAVE_SUCCESS/SAVE_ERROR`. Buttons `CRM_SLA.POLICIES.DIALOG.SAVE` / `CRM_SLA.POLICIES.DIALOG.CANCEL`.

### 7.7 `components/sla/CrmSlaTimeInput.vue` (Pkg F)

`<script setup>` rewrite of the deleted `settings/sla/SlaTimeInput.vue`. Props: `modelValue: { type: Number, default: null }` (threshold in the chosen unit), `unit: { type: String, default: 'Minutes' }`, `label: String`, `placeholder: String`. Emits `update:modelValue`, `update:unit`, `invalid` (boolean). Unit options labels from `CRM_SLA.TIME_UNITS.{MINUTES,HOURS,DAYS}` (values stay `'Minutes'|'Hours'|'Days'` to reuse the SlaForm seconds math). Validation: positive decimal; error copy `CRM_SLA.POLICIES.DIALOG.THRESHOLD_INVALID`.

### 7.8 `components/sla/CrmInboxScheduleList.vue` (Pkg G)

No props. Loads `CrmServiceSchedulesAPI.get()` on mount; uses store getter `inboxes/getInboxes` for the inbox roster. Renders the section title/description (`CRM_SLA.SCHEDULES.TITLE/DESCRIPTION`) and a table of account inboxes with: inbox name, status (`CRM_SLA.SCHEDULES.LIST.CONFIGURED` + timezone, or `NOT_CONFIGURED`), and actions: edit (`i-lucide-calendar-cog`, `CRM_SLA.SCHEDULES.LIST.EDIT`) opening `<CrmScheduleEditor owner-type="Inbox" :owner-id :owner-name :schedule />`; remove (`i-lucide-trash-2`, `CRM_SLA.SCHEDULES.LIST.REMOVE`, only when configured) → `CrmServiceSchedulesAPI.delete(id)` + alert `CRM_SLA.SCHEDULES.EDITOR.API.DELETE_SUCCESS/DELETE_ERROR`. Empty roster shows `CRM_SLA.SCHEDULES.EMPTY`.

### 7.9 `components/sla/CrmScheduleEditor.vue` (Pkg G)

The cal.com-style multi-block editor, used for BOTH inbox and agent calendars. Props:

```js
ownerType: { type: String, required: true },          // 'Inbox' | 'User'
ownerId:   { type: Number, required: true },
ownerName: { type: String, default: '' },
schedule:  { type: Object, default: null },           // existing payload row or null
```

Emits: `close`, `saved` (with the saved schedule payload). Dialog title: `CRM_SLA.SCHEDULES.EDITOR.INBOX_TITLE` or `AGENT_TITLE` (`{name}` interpolation). Content:
- Timezone ComboBox (`dashboard/components-next/combobox/ComboBox.vue`) fed by `timeZoneOptions()` from `dashboard/routes/dashboard/settings/inbox/helpers/businessHour`; label `CRM_SLA.SCHEDULES.EDITOR.TIMEZONE_LABEL`; default `'America/Sao_Paulo'` when creating.
- Enabled toggle (`...ENABLED_LABEL`).
- Seven day rows (`...DAYS.SUNDAY`…`SATURDAY`, JS `wday` order 0..6); each row lists its blocks as two `<input type="time">` (start/end, labels `...START_LABEL/END_LABEL`), an add-block button (`i-lucide-plus`, `...ADD_BLOCK`) and per-block remove (`i-lucide-x`, `...REMOVE_BLOCK`). Day with no blocks shows `...NO_BLOCKS`. Convert `"HH:MM"` ↔ minutes (`h*60+m`); validate `end > start` (`...BLOCK_INVALID`).
- Save (`...SAVE`) → `CrmServiceSchedulesAPI.create({ service_schedule: { owner_type, owner_id, timezone, enabled, blocks } })` (create is an upsert; always use create — no id juggling) + alert `...API.SAVE_SUCCESS/SAVE_ERROR`; Cancel (`...CANCEL`) emits `close`.

### 7.10 Agent dialog (Pkg G — edit `settings/agents/EditAgent.vue`)

LOCKED decision 5 + scope decision: schedule editing lives ONLY in EditAgent (AddAgent untouched — the user must exist to own a calendar). Additions:
- Gate: `const showSlaSchedule = computed(() => window.globalConfig?.CRM_KANBAN_ENABLED === 'true' && isFeatureEnabledonAccount.value(accountId.value, FEATURE_FLAGS.SLA));` using `useMapGetter('accounts/isFeatureEnabledonAccount')`, `useMapGetter('getCurrentAccountId')`, `FEATURE_FLAGS` from `dashboard/featureFlags`.
- Section at the bottom of the form (above action buttons), `v-if="showSlaSchedule"`: title `CRM_SLA.AGENT.SECTION_TITLE`, note `CRM_SLA.AGENT.SECTION_NOTE`, Button (`i-lucide-calendar-clock`, slate/outline) label `CRM_SLA.AGENT.EDIT_BUTTON` → opens `<CrmScheduleEditor owner-type="User" :owner-id="props.id" :owner-name="props.name" :schedule="agentSchedule" />` (import path `dashboard/routes/dashboard/crm/components/sla/CrmScheduleEditor.vue`).
- `agentSchedule` fetched lazily on first open: `CrmServiceSchedulesAPI.get()` then `find(s => s.owner_type === 'User' && s.owner_id === props.id)`.

---

## 8. Settings removal contract (Pkg J)

LOCKED decision 6 — SLA screen leaves Settings for good:
1. `settings.routes.js`: delete line 22 `import sla from './sla/sla.routes';` and line 63 `...sla.routes,`.
2. `Sidebar.vue`: delete the whole "Settings Sla" child object (lines ~847–852: `name: 'Settings Sla'`, label `SIDEBAR.SLA`, icon `i-lucide-clock-alert`, `to: accountScopedRoute('sla_list')`).
3. DELETE directory `app/javascript/dashboard/routes/dashboard/settings/sla/` (7 files listed in §1).
4. Verified importers of `settings/sla/*`: ONLY `settings.routes.js` (import) and `Sidebar.vue` (route name `sla_list`). Nothing else references `sla_list`/`sla_wrapper`/`AddSLA`/`SlaForm`/`SlaTimeInput`/`SLAPaywallEnterprise`.
5. MUST NOT TOUCH: `reports.routes.js` `sla_reports` route, `store/modules/SLAReports`, `SIDEBAR.REPORTS_SLA` entry, `en/sla.json`+`pt_BR/sla.json` (still used by conversation-view SLA UI), `store/modules/sla.js` registration (the new CRM page uses it).
6. Leave the now-unused `SIDEBAR.SLA` i18n key in place (harmless; deleting risks parity churn).

## 9. Sidebar contract (Pkg J — edit `components-next/sidebar/Sidebar.vue`)

1. New computed, placed right after `canViewCrmReports` (~line 113), mirroring its shape but admin-or-crm_admin ONLY (plain agents excluded):

```js
// CRM SLA management is admin-grade: administrators or crm_admin custom-role seats.
const canManageCrmSla = computed(() => {
  if (currentRole.value === 'administrator') return true;
  const permissions = getUserPermissions(currentUser.value, accountId.value);
  return permissions.includes(CRM_ADMIN_PERMISSION);
});
```

2. In the CRM children array, immediately AFTER the `CRM Dashboard` spread block (after its `: []),`), add:

```js
              ...(canManageCrmSla.value
                ? [
                    {
                      name: 'CRM SLA',
                      label: t('SIDEBAR.CRM_SLA'),
                      to: accountScopedRoute('crm_sla_index'),
                      activeOn: ['crm_sla_index'],
                    },
                  ]
                : []),
```

3. Remove the Settings Sla child (§8.2).

---

## 10. i18n — COMPLETE key list (Pkg I owns the 4 json files; everyone else uses ONLY these keys)

### 10.1 `en/settings.json` + `pt_BR/settings.json` — add inside `"SIDEBAR"`, directly after `"CRM_DASHBOARD"`:

| Key | en | pt_BR |
|---|---|---|
| `SIDEBAR.CRM_SLA` | `SLA` | `SLA` |

### 10.2 `en/crm.json` + `pt_BR/crm.json` — add inside `CRM_KANBAN.LIST.COLUMNS`:

| Key | en | pt_BR |
|---|---|---|
| `CRM_KANBAN.LIST.COLUMNS.SLA` | `SLA` | `SLA` |

### 10.3 `en/crm.json` + `pt_BR/crm.json` — new top-level `CRM_SLA` section (after `CRM_INTEGRATION_TOKENS`). en values first, pt_BR second:

```
CRM_SLA.HEADER.TITLE                       = "SLA"                                                  | "SLA"
CRM_SLA.HEADER.DESCRIPTION                 = "Manage SLA policies and service calendars for your CRM." | "Gerencie políticas de SLA e calendários de atendimento do seu CRM."
CRM_SLA.PAYWALL.TITLE                      = "SLA is an enterprise feature"                          | "SLA é um recurso enterprise"
CRM_SLA.PAYWALL.DESCRIPTION                = "Enable the SLA feature for this account to manage policies and calendars." | "Habilite o recurso de SLA nesta conta para gerenciar políticas e calendários."
CRM_SLA.POLICIES.TITLE                     = "Policies"                                              | "Políticas"
CRM_SLA.POLICIES.DESCRIPTION               = "Response and resolution targets applied to conversations." | "Metas de resposta e resolução aplicadas às conversas."
CRM_SLA.POLICIES.ADD                       = "Add policy"                                            | "Nova política"
CRM_SLA.POLICIES.EMPTY                     = "No SLA policies yet. Create the first one."            | "Nenhuma política de SLA ainda. Crie a primeira."
CRM_SLA.POLICIES.TABLE.NAME                = "Name"                                                  | "Nome"
CRM_SLA.POLICIES.TABLE.BUSINESS_HOURS      = "Business hours"                                        | "Horário comercial"
CRM_SLA.POLICIES.TABLE.FRT                 = "First response"                                        | "Primeira resposta"
CRM_SLA.POLICIES.TABLE.NRT                 = "Next response"                                         | "Próxima resposta"
CRM_SLA.POLICIES.TABLE.RT                  = "Resolution"                                            | "Resolução"
CRM_SLA.POLICIES.TABLE.AUTO_APPLY          = "Auto apply"                                            | "Auto-aplicar"
CRM_SLA.POLICIES.TABLE.ACTIONS             = "Actions"                                               | "Ações"
CRM_SLA.POLICIES.BADGES.ENABLED            = "Enabled"                                               | "Ativado"
CRM_SLA.POLICIES.BADGES.DISABLED           = "Disabled"                                              | "Desativado"
CRM_SLA.POLICIES.BADGES.GROUPS_EXCLUDED    = "Groups excluded"                                       | "Grupos excluídos"
CRM_SLA.POLICIES.BADGES.AI_GUARD           = "AI pause guard"                                        | "IA: pausas naturais"
CRM_SLA.POLICIES.BADGES.AUTO_APPLY_ON      = "Auto"                                                  | "Auto"
CRM_SLA.POLICIES.DELETE.TITLE              = "Delete policy"                                         | "Excluir política"
CRM_SLA.POLICIES.DELETE.MESSAGE            = "Are you sure you want to delete {name}? Conversations already using it keep their history." | "Tem certeza de que deseja excluir {name}? Conversas que já a usam mantêm o histórico."
CRM_SLA.POLICIES.DELETE.CONFIRM            = "Yes, delete"                                           | "Sim, excluir"
CRM_SLA.POLICIES.DELETE.CANCEL             = "Cancel"                                                | "Cancelar"
CRM_SLA.POLICIES.API.SAVE_SUCCESS          = "SLA policy saved successfully"                          | "Política de SLA salva com sucesso"
CRM_SLA.POLICIES.API.SAVE_ERROR            = "Could not save the SLA policy, try again"               | "Não foi possível salvar a política de SLA, tente novamente"
CRM_SLA.POLICIES.API.DELETE_SUCCESS        = "SLA policy deleted successfully"                        | "Política de SLA excluída com sucesso"
CRM_SLA.POLICIES.API.DELETE_ERROR          = "Could not delete the SLA policy, try again"             | "Não foi possível excluir a política de SLA, tente novamente"
CRM_SLA.POLICIES.DIALOG.ADD_TITLE          = "Create SLA policy"                                     | "Criar política de SLA"
CRM_SLA.POLICIES.DIALOG.EDIT_TITLE         = "Edit SLA policy"                                       | "Editar política de SLA"
CRM_SLA.POLICIES.DIALOG.NAME.LABEL         = "Name"                                                  | "Nome"
CRM_SLA.POLICIES.DIALOG.NAME.PLACEHOLDER   = "e.g. Priority support"                                 | "ex.: Suporte prioritário"
CRM_SLA.POLICIES.DIALOG.NAME.REQUIRED_ERROR = "Name is required (minimum 2 characters)"              | "Nome é obrigatório (mínimo de 2 caracteres)"
CRM_SLA.POLICIES.DIALOG.DESCRIPTION.LABEL  = "Description"                                           | "Descrição"
CRM_SLA.POLICIES.DIALOG.DESCRIPTION.PLACEHOLDER = "What this policy is for"                          | "Para que serve esta política"
CRM_SLA.POLICIES.DIALOG.FRT.LABEL          = "First response time"                                   | "Tempo de primeira resposta"
CRM_SLA.POLICIES.DIALOG.FRT.PLACEHOLDER    = "e.g. 30"                                               | "ex.: 30"
CRM_SLA.POLICIES.DIALOG.NRT.LABEL          = "Next response time"                                    | "Tempo de próxima resposta"
CRM_SLA.POLICIES.DIALOG.NRT.PLACEHOLDER    = "e.g. 30"                                               | "ex.: 30"
CRM_SLA.POLICIES.DIALOG.RT.LABEL           = "Resolution time"                                       | "Tempo de resolução"
CRM_SLA.POLICIES.DIALOG.RT.PLACEHOLDER     = "e.g. 8"                                                | "ex.: 8"
CRM_SLA.POLICIES.DIALOG.THRESHOLD_INVALID  = "Enter a valid time greater than zero"                   | "Informe um tempo válido maior que zero"
CRM_SLA.POLICIES.DIALOG.BUSINESS_HOURS.LABEL = "Only count business hours"                            | "Contar apenas horário de atendimento"
CRM_SLA.POLICIES.DIALOG.BUSINESS_HOURS.NOTE = "Uses the assigned agent's calendar, then the inbox calendar, otherwise 24/7." | "Usa o calendário do agente atribuído, depois o da caixa de entrada; sem calendário, 24/7."
CRM_SLA.POLICIES.DIALOG.EXCLUDE_GROUPS.LABEL = "Exclude group conversations"                          | "Excluir conversas de grupo"
CRM_SLA.POLICIES.DIALOG.EXCLUDE_GROUPS.NOTE = "WhatsApp groups, broadcasts and newsletters never trigger this SLA." | "Grupos de WhatsApp, broadcasts e newsletters nunca acionam este SLA."
CRM_SLA.POLICIES.DIALOG.AI_SKIP.LABEL      = "AI: skip natural pauses"                                | "IA: não contar pausas naturais"
CRM_SLA.POLICIES.DIALOG.AI_SKIP.NOTE       = "Before counting a breach, AI checks whether a customer is really waiting." | "Antes de contar uma quebra, a IA verifica se um cliente está realmente esperando."
CRM_SLA.POLICIES.DIALOG.AUTO_APPLY.TITLE   = "Apply automatically"                                   | "Aplicar automaticamente"
CRM_SLA.POLICIES.DIALOG.AUTO_APPLY.ENABLED_LABEL = "Apply when a conversation is created"             | "Aplicar ao criar conversa"
CRM_SLA.POLICIES.DIALOG.AUTO_APPLY.NOTE    = "Applies when the conversation lands in a selected inbox OR pipeline. Leave both empty to apply to all." | "Aplica quando a conversa cai numa caixa OU num funil selecionado. Deixe ambos vazios para aplicar a todos."
CRM_SLA.POLICIES.DIALOG.AUTO_APPLY.INBOXES_LABEL = "Inboxes"                                          | "Caixas de entrada"
CRM_SLA.POLICIES.DIALOG.AUTO_APPLY.INBOXES_ALL = "All inboxes"                                        | "Todas as caixas"
CRM_SLA.POLICIES.DIALOG.AUTO_APPLY.PIPELINES_LABEL = "Pipelines"                                      | "Funis"
CRM_SLA.POLICIES.DIALOG.AUTO_APPLY.PIPELINES_ALL = "All pipelines"                                    | "Todos os funis"
CRM_SLA.POLICIES.DIALOG.SAVE               = "Save"                                                  | "Salvar"
CRM_SLA.POLICIES.DIALOG.CANCEL             = "Cancel"                                                | "Cancelar"
CRM_SLA.TIME_UNITS.MINUTES                 = "Minutes"                                               | "Minutos"
CRM_SLA.TIME_UNITS.HOURS                   = "Hours"                                                 | "Horas"
CRM_SLA.TIME_UNITS.DAYS                    = "Days"                                                  | "Dias"
CRM_SLA.SCHEDULES.TITLE                    = "Service calendars"                                     | "Calendários de atendimento"
CRM_SLA.SCHEDULES.DESCRIPTION              = "Working-hour calendars used by the SLA business-hours math. Agent calendars are edited in Settings → Agents." | "Calendários de expediente usados no cálculo de horário do SLA. Calendários de agentes são editados em Configurações → Agentes."
CRM_SLA.SCHEDULES.EMPTY                    = "No inboxes available."                                  | "Nenhuma caixa de entrada disponível."
CRM_SLA.SCHEDULES.LIST.INBOX               = "Inbox"                                                 | "Caixa de entrada"
CRM_SLA.SCHEDULES.LIST.STATUS              = "Status"                                                | "Status"
CRM_SLA.SCHEDULES.LIST.TIMEZONE            = "Timezone"                                              | "Fuso horário"
CRM_SLA.SCHEDULES.LIST.ACTIONS             = "Actions"                                               | "Ações"
CRM_SLA.SCHEDULES.LIST.CONFIGURED          = "Configured"                                            | "Configurado"
CRM_SLA.SCHEDULES.LIST.NOT_CONFIGURED      = "Not configured"                                        | "Não configurado"
CRM_SLA.SCHEDULES.LIST.EDIT                = "Edit calendar"                                         | "Editar calendário"
CRM_SLA.SCHEDULES.LIST.REMOVE              = "Remove calendar"                                       | "Remover calendário"
CRM_SLA.SCHEDULES.EDITOR.INBOX_TITLE       = "Inbox calendar — {name}"                                | "Calendário da caixa — {name}"
CRM_SLA.SCHEDULES.EDITOR.AGENT_TITLE       = "Agent calendar — {name}"                                | "Calendário do agente — {name}"
CRM_SLA.SCHEDULES.EDITOR.TIMEZONE_LABEL    = "Timezone"                                              | "Fuso horário"
CRM_SLA.SCHEDULES.EDITOR.ENABLED_LABEL     = "Calendar enabled"                                      | "Calendário ativo"
CRM_SLA.SCHEDULES.EDITOR.DAYS.SUNDAY       = "Sunday"                                                | "Domingo"
CRM_SLA.SCHEDULES.EDITOR.DAYS.MONDAY       = "Monday"                                                | "Segunda-feira"
CRM_SLA.SCHEDULES.EDITOR.DAYS.TUESDAY      = "Tuesday"                                               | "Terça-feira"
CRM_SLA.SCHEDULES.EDITOR.DAYS.WEDNESDAY    = "Wednesday"                                             | "Quarta-feira"
CRM_SLA.SCHEDULES.EDITOR.DAYS.THURSDAY     = "Thursday"                                              | "Quinta-feira"
CRM_SLA.SCHEDULES.EDITOR.DAYS.FRIDAY       = "Friday"                                                | "Sexta-feira"
CRM_SLA.SCHEDULES.EDITOR.DAYS.SATURDAY     = "Saturday"                                              | "Sábado"
CRM_SLA.SCHEDULES.EDITOR.ADD_BLOCK         = "Add block"                                             | "Adicionar bloco"
CRM_SLA.SCHEDULES.EDITOR.REMOVE_BLOCK      = "Remove block"                                          | "Remover bloco"
CRM_SLA.SCHEDULES.EDITOR.START_LABEL       = "Start"                                                 | "Início"
CRM_SLA.SCHEDULES.EDITOR.END_LABEL         = "End"                                                   | "Fim"
CRM_SLA.SCHEDULES.EDITOR.BLOCK_INVALID     = "End time must be after the start time"                  | "O horário final deve ser depois do inicial"
CRM_SLA.SCHEDULES.EDITOR.NO_BLOCKS         = "Closed"                                                | "Fechado"
CRM_SLA.SCHEDULES.EDITOR.SAVE              = "Save calendar"                                         | "Salvar calendário"
CRM_SLA.SCHEDULES.EDITOR.CANCEL            = "Cancel"                                                | "Cancelar"
CRM_SLA.SCHEDULES.EDITOR.API.SAVE_SUCCESS  = "Calendar saved successfully"                            | "Calendário salvo com sucesso"
CRM_SLA.SCHEDULES.EDITOR.API.SAVE_ERROR    = "Could not save the calendar, try again"                 | "Não foi possível salvar o calendário, tente novamente"
CRM_SLA.SCHEDULES.EDITOR.API.DELETE_SUCCESS = "Calendar removed successfully"                          | "Calendário removido com sucesso"
CRM_SLA.SCHEDULES.EDITOR.API.DELETE_ERROR  = "Could not remove the calendar, try again"               | "Não foi possível remover o calendário, tente novamente"
CRM_SLA.AGENT.SECTION_TITLE                = "Service hours (SLA)"                                   | "Horário de atendimento (SLA)"
CRM_SLA.AGENT.SECTION_NOTE                 = "One calendar per agent; it overrides the inbox calendar in SLA timing." | "Um calendário por agente; ele sobrepõe o calendário da caixa no cálculo do SLA."
CRM_SLA.AGENT.EDIT_BUTTON                  = "Set service hours"                                     | "Definir horário de atendimento"
```

Totals: 97 keys in `CRM_SLA` + 1 `SIDEBAR.CRM_SLA` + 1 `CRM_KANBAN.LIST.COLUMNS.SLA` = **99 new keys per locale** (en and pt_BR, strict 1:1 parity).

---

## 11. Zero-regression checklist (every package re-verifies its slice)

- `only_during_business_hours=false` OR no usable schedule → engine math is wall-clock epoch, arithmetically identical to native (§2.8 proofs). The resolver query never runs for 24/7 policies.
- `exclude_groups` affects ONLY conversations whose `contact_inbox.source_id` matches the denylist; non-WhatsApp/1:1 ids return false fast.
- AI guard is inert unless policy toggle + `Crm::Ai::Config.enabled?` + account `sla` feature + credential all hold; any exception fails open (breach counted).
- Auto-apply only fires from the new `conversation_created` listener hook gated by `Crm::Config.enabled?`; manual/automation `add_sla` flow untouched except the group guard.
- Native WorkingHour model, inbox business-hours feature, conversation SLA UI (`SLACardLabel` in conversation list/popovers), Settings → Reports → SLA: untouched.
- `sla_policies` API: existing fields/params/views unchanged; new fields additive.
- Zeitwerk: `Sla::BusinessTimeCalculator`, `Sla::ScheduleResolver`, `Sla::AiBreachGuard` live in `enterprise/app/services/sla/` (the `Sla::` namespace already exists there); `Crm::ServiceSchedule` follows `Crm::PipelineInbox` (explicit `self.table_name`). Run the eager_load gate.
- ApplicationRecord 255-char cap: no new string column stores longer values (timezone ids max ~30 chars).

## 12. Per-package syntax gates (run before reporting done)

- Ruby: `ruby -c <file>` for every touched `.rb`.
- JS/Vue: `cd /root/docker-stacks/build/chatwoot-campaign-v4.14.1 && npx eslint <file>` (best effort).
- i18n (Pkg I): `node -e "require('./app/javascript/dashboard/i18n/locale/en/crm.json')"` (and pt_BR, settings.json) + key-parity diff en↔pt_BR.
