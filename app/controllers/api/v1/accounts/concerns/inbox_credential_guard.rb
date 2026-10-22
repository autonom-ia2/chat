# Changing how a live inbox connects (logins, passwords, tokens, mail servers, the API inbox webhook) swaps a
# credential of the account: admin or integration_manage (#2027). Every other setting stays with inbox_manage, so
# integration_manage alone saves only how the inbox connects.
# Only values that actually change count, because the settings forms send the whole channel back.
# Passwords and tokens pasted from other systems only go back to administrators, so a blank one keeps what is stored,
# but only while the mail server stays the same: pointing it elsewhere asks for the password again, or the stored one
# would be sent to a server nobody checked.
module Api::V1::Accounts::Concerns::InboxCredentialGuard
  extend ActiveSupport::Concern

  CREDENTIAL_ATTRS = %w[
    imap_enabled imap_login imap_password imap_address imap_port imap_enable_ssl imap_authentication
    smtp_enabled smtp_login smtp_password smtp_address smtp_port smtp_domain smtp_authentication
    smtp_enable_ssl_tls smtp_enable_starttls_auto smtp_openssl_verify_mode
    line_channel_id line_channel_secret line_channel_token
    bot_token account_sid auth_token api_key_sid api_key_secret
    provider provider_config webhook_url
  ].freeze
  SECRET_ATTRS = %w[imap_password smtp_password line_channel_secret line_channel_token bot_token auth_token api_key_secret].freeze
  # Where each mail password is sent: pointing it to another server needs the password typed again.
  SECRET_DESTINATIONS = {
    'imap_password' => %w[imap_address imap_port],
    'smtp_password' => %w[smtp_address smtp_port]
  }.freeze

  # Inbox settings that are not about connecting it; with them, integration_manage alone is not enough.
  INBOX_SETTINGS_PARAMS = %i[working_hours branded_email_layout].freeze

  private

  def check_credential_change
    check_permission_granted!('inbox_manage') if inbox_settings_change_requested?
    return unless credential_change_requested?

    check_permission_granted!('integration_manage')
    render_password_needed if stored_secret_would_move?
  end

  # The channel attributes this update will save, typed by the same permit the update uses, minus blank secrets.
  def channel_update_params
    submitted = permitted_params(get_channel_attributes(@inbox.channel_type))[:channel]
    return {} if submitted.blank?

    submitted.reject { |attr, value| SECRET_ATTRS.include?(attr.to_s) && value.blank? }
  end

  # What the mail server test needs: a blank password stands for the stored one.
  def channel_params_with_stored_secrets
    stored = SECRET_ATTRS.index_with { |attr| @inbox.channel.try(attr) }.compact
    stored.merge(channel_update_params.to_h).with_indifferent_access
  end

  def credential_change_requested?
    submitted = channel_update_params
    CREDENTIAL_ATTRS.any? do |attr|
      submitted.key?(attr) && @inbox.channel.respond_to?(attr) && changed_value?(submitted[attr], @inbox.channel.public_send(attr))
    end
  end

  def inbox_settings_change_requested?
    INBOX_SETTINGS_PARAMS.any? { |key| params.key?(key) } || channel_setting_changed? ||
      permitted_params.except(:channel).to_h.any? { |attr, value| changed_value?(value, @inbox.try(attr)) }
  end

  def channel_setting_changed?
    submitted = channel_update_params
    (submitted.keys.map(&:to_s) - CREDENTIAL_ATTRS).any? do |attr|
      @inbox.channel.respond_to?(attr) && changed_value?(submitted[attr], @inbox.channel.public_send(attr))
    end
  end

  # A blank mail password on a save that points the mailbox elsewhere.
  def stored_secret_would_move?
    submitted = permitted_params(get_channel_attributes(@inbox.channel_type))[:channel] || {}
    SECRET_DESTINATIONS.any? do |secret, destination|
      submitted[secret].blank? && @inbox.channel.try(secret).present? &&
        destination.any? { |attr| submitted.key?(attr) && changed_value?(submitted[attr], @inbox.channel.try(attr)) }
    end
  end

  def render_password_needed
    render json: { message: I18n.t('errors.inboxes.password_needed') }, status: :unprocessable_entity
  end

  # The forms send unset switches as false and unset fields as blank where the database keeps nil: none of them is a change.
  def changed_value?(submitted, current)
    return comparable_hash(submitted) != comparable_hash(current) if submitted.respond_to?(:to_unsafe_h) || submitted.is_a?(Hash)
    return false if unset?(submitted) && unset?(current)

    submitted.to_s != current.to_s
  end

  def unset?(value)
    value.nil? || value.to_s.empty? || value.to_s == 'false'
  end

  def comparable_hash(value)
    hash = value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value.to_h
    hash.deep_stringify_keys.transform_values(&:to_s)
  end
end
