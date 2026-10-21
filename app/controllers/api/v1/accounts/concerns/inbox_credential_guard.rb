# Changing how a live inbox connects (logins, passwords, tokens, mail servers, the API inbox webhook) swaps a
# credential of the account: admin or integration_manage (#2027). Every other setting stays with inbox_manage.
# Only values that actually change count, because the settings forms send the whole channel back.
# Passwords and tokens pasted from other systems only go back to administrators, so a blank one keeps what is stored.
module Api::V1::Accounts::Concerns::InboxCredentialGuard
  extend ActiveSupport::Concern

  CREDENTIAL_ATTRS = %w[
    imap_login imap_password imap_address imap_port
    smtp_login smtp_password smtp_address smtp_port smtp_domain
    line_channel_id line_channel_secret line_channel_token
    bot_token account_sid auth_token api_key_sid api_key_secret
    provider provider_config webhook_url
  ].freeze
  SECRET_ATTRS = %w[imap_password smtp_password line_channel_secret line_channel_token bot_token auth_token api_key_secret].freeze

  private

  def check_credential_change
    check_permission_granted!('integration_manage') if credential_change_requested?
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

  def changed_value?(submitted, current)
    return comparable_hash(submitted) != comparable_hash(current) if submitted.respond_to?(:to_unsafe_h) || submitted.is_a?(Hash)

    submitted.to_s != current.to_s
  end

  def comparable_hash(value)
    hash = value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value.to_h
    hash.deep_stringify_keys.transform_values(&:to_s)
  end
end
