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
# - 'conversation_message_delete': Can delete messages in the conversations they operate (#1893). Agents without a
#   custom role keep deleting as before.
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
# - 'crm_delete_cards': Can archive CRM cards, one by one or in bulk (split from crm_manage_cards in #1874; roles that
#   had crm_manage_cards kept it).
# - 'crm_metas_manage': Can see and set every person's monthly goal in CRM › Números (Metas do mês, #1991). crm_admin
#   implies it; agents without a custom role never get it.
# Every CRM editing key (CRM_EDITING_KEYS) implies crm_view: the role is saved with crm_view added (#2124), so the
# policies, booking host eligibility, live updates, integration token scopes and the panel all read the same keys.
# crm_view_reports (reports only) and sales_value_view (money) do not imply it.
#
# Module keys: '<module>_manage' implies '<module>_view' (see Enterprise::AccountUser#permission_granted?).
# - 'contact_view' / 'knowledge_base_view': read-only access to contacts / help center.
# - 'contact_export': export the contact base (split from contact_manage in #1845; roles that had contact_manage kept it).
# - 'contact_delete': delete contacts and companies, one by one or in bulk (#1845).
# - 'autonomia_view': view and test Autonom.ia agents. 'autonomia_manage': create, train and publish them.
# - 'desempenho_view': the agent performance panel and its PDF/spreadsheet export (#2251). Independent from
#   autonomia_view; the panel shows a conversation only to who sees its inbox. View only (no _manage).
# - 'campaign_view': view campaigns and their reports. 'campaign_manage': build campaigns and import lists.
#   'campaign_send': send, schedule and resume them (#1898; roles that had campaign_manage kept sending).
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
#   only the conversations the person already sees. It also shows each ad's budget and dates in R$ and the ads created
#   here that are still paused (#2198).
# - 'meta_ads_manage': connect, configure and disconnect Meta Ads (token, Facebook login, ad account and Pixel choice,
#   destinations, funnel sale signal, insights refresh, the owner's WhatsApp report) and act on the advisor (#2070).
#   It also pauses and activates ads (#2161; activating is what spends), creates new ads (always born paused), uploads
#   photos and videos to the ad account, and changes an ad's budget and end date (#2198).
#   Protected key (two-list rule, #1782; decision D7 of lote 11): only an administrator hands it out, or whoever holds
#   grant_above_own, which only an administrator turns on. Choosing an ad account grants the platform system user
#   access to the client's ad account. CRM sales values are out of its scope (sales_value_view, lote 13); the ad
#   budget it shows and changes is the ad's own money at Meta, in the ad account's currency (#2198).
# - 'posts_view' / 'posts_manage': Seus posts (#2302), the Instagram and Facebook Page posts of the account's inboxes.
#   view sees the profile numbers and the posts; the comments (who wrote them) also need to see the inbox
#   (InboxPolicy#show?). manage answers, hides and shows a comment again and sends the private reply, also only on
#   inboxes the person sees. Common delegable module (Funções, 27/10).
# - 'label_manage', 'attribute_manage', 'macro_manage' (team-wide macros), 'sla_manage': account settings.
# - 'assignment_manage': assignment and agent capacity policies, and which policy each inbox uses (#1797).
# - 'people_manage': add, invite, edit and remove agents, and manage teams (#1931). Never administrators, never one's own
#   access (CustomRoles::GrantGuard and AccountUsers::AccessGuard).
# - 'custom_role_manage': create, edit and delete custom roles, within one's own keys (#1931).
# - 'grant_above_own': with people_manage or custom_role_manage, hand out any custom role of the account, even above
#   one's own; never administrator. The audit log is the safeguard (#1931).
# - 'financial_view': the account's costs in money: AI usage values (R$/US$, CSV, live push) and the Meta charge
#   authorization screen (#1969). 'financial_manage': turn the Meta charge authorization on and off. Plan, invoices and
#   payments (Financeiro module) stay with administrators.
# - 'integration_manage': connect, configure and disconnect integrations (Slack, Linear, Notion, Shopify, dashboard apps,
#   imports), webhooks and agent bots, and swap the credentials of an existing inbox (#2027). Creating an inbox stays
#   with inbox_manage. Credentials pasted from other systems are never shown back to it.
# - 'token_manage': see and rotate the secrets the platform issues (inbox HMAC and API secret, webhook signing secret,
#   agent bot token and secret, CRM integration tokens, Google conversion feed), never minting more than one holds (#2027).
# - 'sales_value_view': see sales values in money in the CRM: card value, sums, goals in money and ratios taken from
#   money (ROI, % of goal, win rate by value). Without it, counts stay, and a person still sees the value of the cards
#   they own and their own numbers. A delegation key, so crm_admin does not imply it; agents without a custom role keep
#   seeing values (#2075).

class CustomRole < ApplicationRecord
  belongs_to :account
  has_many :account_users, dependent: :nullify

  # Roles behind integration tokens (Crm/Mcp::IntegrationToken) belong to a hidden integration member. They are managed
  # by the token screens and never listed, edited or handed out as a person's role (#1931).
  scope :for_people, lambda {
    where.not(id: AccountUser.where(integration: true).where.not(custom_role_id: nil).select(:custom_role_id))
  }

  before_validation :add_implied_permissions
  before_validation :strip_name
  before_destroy :capture_filtered_unread_count_user_ids, prepend: true
  after_update_commit :invalidate_filtered_unread_count_visibility_update, if: :filtered_unread_count_permissions_changed?
  after_destroy_commit :invalidate_filtered_unread_count_visibility_destroy

  PERMISSIONS = %w[
    conversation_manage
    conversation_unassigned_manage
    conversation_participating_manage
    conversation_view
    conversation_message_delete
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
    crm_delete_cards
    crm_metas_manage
    contact_view
    contact_export
    contact_delete
    knowledge_base_view
    autonomia_view
    autonomia_manage
    desempenho_view
    campaign_view
    campaign_manage
    campaign_send
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
    meta_ads_manage
    posts_view
    posts_manage
    label_manage
    attribute_manage
    macro_manage
    sla_manage
    assignment_manage
    people_manage
    custom_role_manage
    grant_above_own
    financial_view
    financial_manage
    integration_manage
    token_manage
    sales_value_view
  ].freeze

  # Delegable keys only an administrator hands out, unless the giver has grant_above_own (CLAUDE.md, #1931).
  DELEGATION_KEYS = %w[people_manage custom_role_manage grant_above_own financial_view financial_manage integration_manage
                       token_manage meta_ads_manage sales_value_view].freeze

  # Editing the CRM needs seeing it (#2124). crm_view_reports and sales_value_view stay apart.
  CRM_EDITING_KEYS = %w[crm_manage_cards crm_move_cards crm_manage_pipelines crm_manage_ai crm_delete_cards crm_metas_manage
                        crm_export].freeze

  # The keys as the role stores them: an editing key brings crm_view along. Readers check the stored keys, and the grant
  # guard checks these, so nobody hands out a crm_view they do not hold.
  def self.with_implied_permissions(permissions)
    keys = Array(permissions).map(&:to_s)
    return keys if keys.include?('crm_view') || !keys.intersect?(CRM_EDITING_KEYS)

    keys + ['crm_view']
  end

  # Um nome por conta, sem diferenciar maiúsculas nem espaços nas pontas (#2185): duas "Vendas" confundem quem dá a
  # função. O índice único em lower(trim(name)) segura duas gravações ao mesmo tempo.
  # Só confere quando o nome muda, para não consultar o banco a cada troca de chaves.
  validates :name, presence: true
  validate :name_not_taken, if: :will_save_change_to_name?
  # The inclusion validator stays: tools read the accepted keys from it (#900). The message
  # names the rejected keys and the accepted ones, so a person or the Guide can fix the
  # request instead of guessing (#894).
  validates :permissions, inclusion: { in: PERMISSIONS, message: ->(role, _data) { role.unknown_permissions_message } }

  def unknown_permissions_message
    unknown = Array(permissions) - PERMISSIONS
    I18n.t('errors.custom_role.unknown_permissions', unknown: unknown.join(', '), valid: PERMISSIONS.join(', '))
  end

  private

  # A mesma conta que o índice faz (lower(trim(name))): um nome antigo salvo com espaço nas pontas também conta.
  def name_not_taken
    return if name.blank?

    taken = self.class.where(account_id: account_id).where.not(id: id).exists?(['lower(trim(name)) = ?', name.downcase])
    errors.add(:name, :taken) if taken
  end

  def strip_name
    self.name = name.strip if name.is_a?(String)
  end

  def add_implied_permissions
    self.permissions = self.class.with_implied_permissions(permissions)
  end

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

CustomRole.include Enterprise::Audit::CustomRole
