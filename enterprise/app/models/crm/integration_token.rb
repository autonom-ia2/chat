# == Schema Information
#
# Table name: crm_integration_tokens
#
#  id              :bigint           not null, primary key
#  last_used_at    :datetime
#  name            :string           not null
#  status          :integer          default("active"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  account_user_id :bigint
#  created_by_id   :bigint
#  custom_role_id  :bigint
#
# Indexes
#
#  index_crm_integration_tokens_on_account_id       (account_id)
#  index_crm_integration_tokens_on_account_user_id  (account_user_id)
#  index_crm_integration_tokens_on_created_by_id    (created_by_id)
#  index_crm_integration_tokens_on_custom_role_id   (custom_role_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (account_user_id => account_users.id) ON DELETE => nullify
#  fk_rails_...  (created_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (custom_role_id => custom_roles.id) ON DELETE => nullify
#

# Per-account, scoped, revocable CRM integration token (plan §3.2, D1 — HubSpot
# Private App style). Modeled like AgentBot: account-scoped owner of an
# AccessToken (via AccessTokenable). On create it provisions a managed CustomRole
# (permissions = the chosen crm_* scopes) plus a hidden AccountUser (role: agent,
# integration: true) so the EE CrmPermissions policy resolves the token to a real
# account_user with a granular custom_role — NOT the blank-custom_role superuser
# fallback (enterprise/app/policies/crm_permissions.rb:15).
#
# EE-only: references CustomRole (EE). Lives under enterprise/ so CE builds never
# autoload it (B-T3).
class Crm::IntegrationToken < ApplicationRecord
  include AccessTokenable

  self.table_name = 'crm_integration_tokens'

  # Subset of CustomRole::PERMISSIONS that an integration token may carry.
  ASSIGNABLE_SCOPES = %w[
    crm_view
    crm_manage_cards
    crm_move_cards
    crm_manage_pipelines
    crm_manage_ai
    crm_view_reports
    crm_admin
  ].freeze

  belongs_to :account
  belongs_to :custom_role, optional: true
  belongs_to :account_user, optional: true
  belongs_to :created_by, class_name: 'User', optional: true

  enum status: { active: 0, revoked: 1 }

  # Virtual: the crm_* scopes chosen at creation time. Persisted onto the managed
  # CustomRole, not on this row.
  attr_accessor :scopes

  validates :name, presence: true
  validate :validate_scopes, on: :create

  before_create :provision_managed_access

  def available_name
    name
  end

  # Permissions currently granted to this token (via its managed CustomRole).
  def granted_scopes
    custom_role&.permissions || []
  end

  private

  def normalized_scopes
    Array(scopes).map(&:to_s).uniq & ASSIGNABLE_SCOPES
  end

  def validate_scopes
    return if normalized_scopes.present?

    errors.add(:scopes, 'must include at least one crm_* permission')
  end

  # Build the managed CustomRole + hidden AccountUser + backing User inside the
  # create transaction so the token never persists half-provisioned.
  def provision_managed_access
    role = account.custom_roles.create!(
      name: "crm_integration_#{SecureRandom.hex(6)}",
      description: "Managed role for CRM integration token: #{name}",
      permissions: normalized_scopes
    )
    user = build_integration_user
    membership = account.account_users.create!(
      user: user,
      role: :agent,
      integration: true,
      custom_role: role
    )

    self.custom_role = role
    self.account_user = membership
  end

  def build_integration_user
    User.create!(
      name: "CRM Integration (#{name})",
      email: "crm-integration+#{SecureRandom.hex(10)}@integration.invalid",
      # Satisfies the password_has_required_content rules (1 upper/lower/number/
      # special). This account never logs in interactively — auth is via the token.
      password: random_login_disabled_password,
      confirmed_at: Time.current
    )
  end

  def random_login_disabled_password
    "Aa1!#{SecureRandom.alphanumeric(28)}"
  end
end
