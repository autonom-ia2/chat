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
#
# Module keys: '<module>_manage' implies '<module>_view' (see Enterprise::AccountUser#permission_granted?).
# - 'contact_view' / 'knowledge_base_view': read-only access to contacts / help center.
# - 'autonomia_view': view and test Autonom.ia agents. 'autonomia_manage': create, train and publish them.
# - 'campaign_view': view campaigns and their reports. 'campaign_manage': create, send and import lists.
# - 'inbox_view': view every inbox configuration. 'inbox_manage': create, connect and configure inboxes.
# - 'canned_response_manage': create, edit and delete canned responses.
# - 'prospecting_view' / 'prospecting_manage': prospecting searches, leads and lists.
# - 'insurance_view' / 'insurance_manage': insurance quoting (Cotação) connection and quote agent.
# - 'automation_view' / 'automation_manage': automation rules.
# - 'label_manage', 'attribute_manage', 'macro_manage' (team-wide macros), 'sla_manage': account settings.

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
    contact_view
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
    insurance_view
    insurance_manage
    automation_view
    automation_manage
    label_manage
    attribute_manage
    macro_manage
    sla_manage
  ].freeze

  validates :name, presence: true
  validates :permissions, inclusion: { in: PERMISSIONS }

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
