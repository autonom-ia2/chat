# frozen_string_literal: true

class Autonomia::Sso::Provisioner
  pattr_initialize [:context!, { token: nil }]

  attr_reader :post_login_redirect_path

  def perform
    pending_invitation = nil
    user = nil
    account = nil

    ActiveRecord::Base.transaction do
      user = find_or_create_user
      account = find_or_create_account
      pending_invitation = pending_agent_invitation(account)
      link_user(user)
      ensure_account_user(user, account, pending_invitation)
    end

    apply_pending_agent_invitation!(user, account, pending_invitation) if pending_invitation.present?
    set_pending_invite_connection_redirect(user, account) if @post_login_redirect_path.blank?
    user
  end

  private

  def find_or_create_user
    linked_user || User.from_email(identity_email) || create_user
  end

  def find_or_create_account
    pending_agent_invitation_account ||
      registration_checkout_account ||
      confirmed_account_link ||
      invited_linked_account ||
      raise_untrusted_account!
  end

  def create_user
    user = User.new(
      email: identity_email,
      name: identity_name.presence || identity_email,
      password: random_password,
      password_confirmation: random_password
    )
    user.skip_confirmation!
    user.save!
    user
  end

  def link_user(user)
    Autonomia::UserLink.find_or_initialize_by(identity_user_id: identity_user_id).tap do |link|
      link.user = user
      link.email = identity_email
      link.metadata = (link.metadata || {}).merge('identity_user' => identity_user)
      link.save!
      Autonomia::Sso::TokenStore.write!(link, token) if token.present?
    end
  end

  def ensure_account_user(user, account, pending_invitation)
    AccountUser.find_or_initialize_by(user: user, account: account).tap do |account_user|
      if pending_invitation.present?
        account_user.role = pending_invitation.fetch('role', nil).presence || 'administrator'
        if pending_invitation.fetch('custom_role_id', nil).present?
          account_user.custom_role_id = pending_invitation['custom_role_id']
        end
        account_user.inviter_id ||= pending_invitation['invited_by_user_id']
      elsif account_user.new_record?
        account_user.role = 'administrator'
      end
      account_user.save!
    end
  end

  def apply_pending_agent_invitation!(user, account, pending_invitation)
    assign_existing_inboxes!(user, account, pending_invitation)
    create_whatsapp_api_inbox!(user, account, pending_invitation)
    consume_pending_agent_invitation(account)
  end

  def assign_existing_inboxes!(user, account, pending_invitation)
    inbox_ids = Array(pending_invitation['inbox_ids']).filter_map do |value|
      value.to_i if value.to_s.match?(/\A\d+\z/)
    end.uniq

    account.inboxes.where(id: inbox_ids).find_each do |inbox|
      InboxMember.find_or_create_by!(inbox: inbox, user: user)
    end
  end

  def create_whatsapp_api_inbox!(user, account, pending_invitation)
    return unless ActiveModel::Type::Boolean.new.cast(pending_invitation['create_whatsapp_api_inbox'])

    result = Waha::InboxProvisioner.new(
      account: account,
      phone: pending_invitation['whatsapp_api_phone'],
      display_name: user.name,
      api_access_token: api_access_token_for(pending_invitation, fallback_user: user)
    ).perform

    InboxMember.find_or_create_by!(inbox: result.inbox, user: user)
    mark_invite_connection_pending!(result.inbox, user)
    @post_login_redirect_path = invite_connection_path(account)
  end

  def api_access_token_for(pending_invitation, fallback_user:)
    token_owner = User.find_by(id: pending_invitation['invited_by_user_id']) || fallback_user
    (token_owner.access_token || token_owner.create_access_token).token
  end

  def mark_invite_connection_pending!(inbox, user)
    channel = inbox.channel
    attrs = (channel.additional_attributes || {}).to_h
    channel.update!(
      additional_attributes: attrs.merge(
        'autonomia_invite_connection' => {
          'user_id' => user.id,
          'status' => 'pending',
          'created_at' => Time.current.iso8601
        }
      )
    )
  end

  def set_pending_invite_connection_redirect(user, account)
    return if invite_connection_inbox(user, account).blank?

    @post_login_redirect_path = invite_connection_path(account)
  end

  def invite_connection_inbox(user, account)
    account.inboxes.where(channel_type: 'Channel::Api').includes(:channel).find do |inbox|
      attrs = (inbox.channel.additional_attributes || {}).to_h
      connection = attrs['autonomia_invite_connection'] || {}
      connection['user_id'].to_i == user.id && connection['status'] != 'connected'
    end
  end

  def invite_connection_path(account)
    "/app/accounts/#{account.id}/autonomia/invite-connection"
  end

  def pending_agent_invitation(account)
    pending_agent_invitations(account)[identity_email.downcase]
  end

  def pending_agent_invitation_account
    Account.where(
      "custom_attributes -> 'autonomia_pending_agent_invitations' ? :email",
      email: identity_email.downcase
    ).first
  end

  def consume_pending_agent_invitation(account)
    invitations = pending_agent_invitations(account)
    invitations.delete(identity_email.downcase)
    account.update!(
      custom_attributes: (account.custom_attributes || {}).merge(
        'autonomia_pending_agent_invitations' => invitations
      )
    )
  end

  def pending_agent_invitations(account)
    (account.custom_attributes || {}).fetch('autonomia_pending_agent_invitations', {})
  end

  def linked_user
    Autonomia::UserLink.find_by(identity_user_id: identity_user_id)&.user
  end

  def confirmed_account_link
    Autonomia::AccountLink
      .where("metadata -> 'registration_checkout' ->> 'auth_user_id' = ?", identity_user_id)
      .includes(:account)
      .first
      &.account
  end

  def invited_linked_account
    user = linked_user
    return if user.blank?

    user.account_users
        .human
        .where.not(inviter_id: nil)
        .includes(:account)
        .order(Arel.sql('active_at DESC NULLS LAST'), created_at: :desc, id: :desc)
        .first
        &.account
  end

  def raise_untrusted_account!
    raise 'Autonomia SSO requires an invitation, provisioned checkout, or confirmed account link.'
  end

  def registration_checkout_account
    Account
      .where(
        "LOWER(custom_attributes -> 'autonomia_registration_checkout' ->> 'email') = :email",
        email: identity_email.downcase
      )
      .order(:id)
      .first
  end

  def identity_user
    context['user'] || {}
  end

  def identity_user_id
    identity_user['id'] || identity_user['sub'] || identity_user['cognitoSub'] || identity_user['cognito_sub'] || identity_email
  end

  def identity_email
    identity_user.fetch('email')
  end

  def identity_name
    identity_user['name'] ||
      identity_user['fullName'] ||
      identity_user['full_name'] ||
      identity_user['displayName'] ||
      identity_user['display_name']
  end

  def random_password
    @random_password ||= "#{SecureRandom.hex(24)}aA1!"
  end
end
