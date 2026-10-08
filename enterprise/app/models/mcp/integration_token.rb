class Mcp::IntegrationToken < ApplicationRecord
  include AccessTokenable

  self.table_name = 'mcp_integration_tokens'

  ASSIGNABLE_SCOPES = %w[
    agents:inboxes:read
    agents:conversations:read
    agents:messages:read
    agents:contacts:read
    agents:agents:read
    agents:reports:read
    agents:messages:send
  ].freeze
  DEFAULT_SCOPES = ASSIGNABLE_SCOPES

  belongs_to :account
  belongs_to :custom_role, optional: true
  belongs_to :account_user, optional: true
  belongs_to :created_by, class_name: 'User', optional: true

  enum status: { active: 0, revoked: 1 }

  validates :identity_subject, presence: true, uniqueness: { scope: :account_id }
  validates :name, presence: true
  validate :validate_scopes

  before_create :provision_managed_access

  def available_name
    name
  end

  def granted_scopes
    scopes
  end

  def rotate_access_token!
    with_lock do
      AccessToken.where(owner: self).delete_all
      AccessToken.create!(owner: self)
    end
  end

  def revoke!
    with_lock do
      update!(status: :revoked)
      AccessToken.where(owner: self).delete_all
      managed_account_user = account_user
      managed_custom_role = custom_role
      managed_account_user&.destroy!
      managed_custom_role&.destroy!
      destroy!
    end
  end

  private

  def validate_scopes
    normalized = Array(scopes).map(&:to_s).uniq
    errors.add(:scopes, 'must include at least one permitted Agents scope') if normalized.blank?
    unknown = normalized - ASSIGNABLE_SCOPES
    errors.add(:scopes, "contains unsupported scopes: #{unknown.join(', ')}") if unknown.present?
    self.scopes = normalized
  end

  def provision_managed_access
    role = account.custom_roles.create!(
      name: "mcp_integration_#{SecureRandom.hex(6)}",
      description: "Managed role for MCP integration token: #{name}",
      permissions: chatwoot_permissions
    )
    user = User.create!(
      name: "MCP Integration (#{name})",
      email: "mcp-integration+#{SecureRandom.hex(10)}@integration.invalid",
      password: "Aa1!#{SecureRandom.alphanumeric(28)}",
      confirmed_at: Time.current
    )
    membership = account.account_users.create!(
      user: user,
      role: :agent,
      integration: true,
      custom_role: role
    )

    self.custom_role = role
    self.account_user = membership
  end

  def chatwoot_permissions
    permissions = []
    permissions << 'conversation_manage' if scopes.any? { |scope| scope.start_with?('agents:conversation', 'agents:message') }
    permissions << 'contact_view' if scopes.include?('agents:contacts:read')
    permissions << 'inbox_view' if scopes.include?('agents:inboxes:read')
    permissions << 'report_manage' if scopes.include?('agents:reports:read')
    permissions.uniq
  end
end
