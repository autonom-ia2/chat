# == Schema Information
#
# Table name: custom_roles
#
#  id          :bigint           not null, primary key
#  description :string
#  name        :string
#  permissions :text             default([]), is an Array
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#
# Indexes
#
#  index_custom_roles_on_account_id  (account_id)
#
#

# Available permissions for custom roles:
# - 'conversation_manage': Can manage all conversations.
# - 'conversation_unassigned_manage': Can manage unassigned conversations and assign to self.
# - 'conversation_participating_manage': Can manage conversations they are participating in (assigned to or a participant).
# - 'conversation_view': Can read every conversation of their inboxes (messages and notes) without operating on them.
#   Writes keep requiring the trio above (#1800).
# - 'contact_manage': Can manage contacts.
# - 'report_manage': Can manage reports.
# - 'knowledge_base_manage': Can manage knowledge base portals.
# - 'crm_view': Can view the CRM module (board/cards read-only).
# - 'crm_manage_cards': Can create/edit/delete CRM cards, links and follow-ups.
# - 'crm_move_cards': Can drag CRM cards between stages.
# - 'crm_manage_pipelines': Can manage CRM pipelines, stages, automations and inbox settings.
# - 'crm_manage_ai': Can manage CRM AI settings and trigger/accept AI suggestions.
# - 'crm_view_reports': Can view CRM reports (forward-looking).
# - 'crm_admin': Umbrella that implies every crm_* permission.
# - 'crm_export': Can download the CRM list as a spreadsheet (personal data in bulk).
#
# Module keys: '<module>_manage' implies '<module>_view' (see Enterprise::AccountUser#permission_granted?).
# - 'contact_view' / 'knowledge_base_view': read-only access to contacts / help center.
# - 'contact_export': export the contact base (split from contact_manage in #1845; roles that had contact_manage kept it).
# - 'contact_delete': delete contacts and companies, one by one or in bulk (#1845).
# - 'autonomia_view': view and test Autonom.ia agents. 'autonomia_manage': create, train and publish them.
# - 'campaign_view': view campaigns and their reports. 'campaign_manage': create, send and import lists.
# - 'inbox_view': view every inbox configuration. 'inbox_manage': create, connect and configure inboxes.
# - 'canned_response_manage': create, edit and delete canned responses.
# - 'prospecting_view' / 'prospecting_manage': prospecting searches, leads and lists.
# - 'prospecting_view_all_searches': see every search of the account (and its leads), not only one's own (#732).
# - 'insurance_view' / 'insurance_manage': insurance quoting (Cotação) connection and quote agent.
# - 'automation_view' / 'automation_manage': automation rules.
# - 'agendamento_view' / 'agendamento_manage': booking pages (Configurações › Agendamento) and their numbers.
#   manage creates, publishes and pauses pages. Hosting a booking or scheduling for a client needs no key.
# - 'whatsapp_templates_view' / 'whatsapp_templates_manage': WhatsApp (Cloud) message templates of the inboxes (#1330).
#   manage creates, edits, duplicates and deletes them at Meta; platform templates stay read-only.
# - 'meta_ads_view': Meta Ads panel, connection state and the panel AI (#1794). Lists that lead to a conversation show
#   only the conversations the person already sees. Connecting and configuring stay with administrators.
# - 'label_manage', 'attribute_manage', 'macro_manage' (team-wide macros), 'sla_manage': account settings.
# - 'assignment_manage': assignment and agent capacity policies, and which policy each inbox uses (#1797).

class CustomRole < ApplicationRecord
  belongs_to :account
  has_many :account_users, dependent: :nullify

  before_destroy :capture_filtered_unread_count_user_ids, prepend: true
  after_update_commit :invalidate_filtered_unread_count_visibility_update, if: :filtered_unread_count_permissions_changed?
  after_destroy_commit :invalidate_filtered_unread_count_visibility_destroy

  PERMISSIONS = %w[
    conversation_manage
    conversation_unassigned_manage
    conversation_participating_manage
    conversation_view
    contact_manage
    report_manage
    knowledge_base_manage
    crm_view
    crm_manage_cards
    crm_move_cards
    crm_manage_pipelines
    crm_manage_ai
    crm_view_reports
    crm_admin
    crm_export
    contact_view
    contact_export
    contact_delete
    knowledge_base_view
    autonomia_view
    autonomia_manage
    campaign_view
    campaign_manage
    inbox_view
    inbox_manage
    canned_response_manage
    prospecting_view
    prospecting_manage
    prospecting_view_all_searches
    insurance_view
    insurance_manage
    automation_view
    automation_manage
    agendamento_view
    agendamento_manage
    whatsapp_templates_view
    whatsapp_templates_manage
    meta_ads_view
    label_manage
    attribute_manage
    macro_manage
    sla_manage
    assignment_manage
  ].freeze

  validates :name, presence: true
  # The inclusion validator stays: tools read the accepted keys from it (#900). The message
  # names the rejected keys and the accepted ones, so a person or the Guide can fix the
  # request instead of guessing (#894).
  validates :permissions, inclusion: { in: PERMISSIONS, message: ->(role, _data) { role.unknown_permissions_message } }

  def unknown_permissions_message
    unknown = Array(permissions) - PERMISSIONS
    I18n.t('errors.custom_role.unknown_permissions', unknown: unknown.join(', '), valid: PERMISSIONS.join(', '))
  end

  private

  def filtered_unread_count_permissions_changed?
    previous_changes.key?('permissions')
  end

  def capture_filtered_unread_count_user_ids
    @filtered_unread_count_user_ids = account_users.pluck(:user_id)
  end

  def invalidate_filtered_unread_count_visibility_update
    invalidate_filtered_unread_count_visibility(account_users.pluck(:user_id))
  end

  def invalidate_filtered_unread_count_visibility_destroy
    invalidate_filtered_unread_count_visibility(@filtered_unread_count_user_ids)
  end

  def invalidate_filtered_unread_count_visibility(user_ids)
    invalidator = ::Conversations::UnreadCounts::FilteredCountInvalidator.new(account)
    visibility_changed = invalidator.users_visibility_changed!(user_ids: user_ids)

    dispatch_account_cache_invalidated if visibility_changed
  end

  def dispatch_account_cache_invalidated
    Rails.configuration.dispatcher.dispatch(ACCOUNT_CACHE_INVALIDATED, Time.zone.now, account: account, cache_keys: account.cache_keys)
  end
end
