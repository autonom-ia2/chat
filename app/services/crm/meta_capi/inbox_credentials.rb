# The Meta credential behind an inbox, for the Conversions API sends (#1940): the official
# WhatsApp channel, its token and its WABA id. Reuses the channel credential (no new secret
# storage). Any other kind of inbox (API, WAHA, SMS) has no Meta token, so it yields nils.
module Crm::MetaCapi::InboxCredentials
  module_function

  def for(inbox)
    channel = inbox&.channel
    return { channel: nil, access_token: nil, waba_id: nil } unless channel.is_a?(Channel::Whatsapp)

    config = channel.provider_config.to_h
    { channel: channel, access_token: config['api_key'].presence, waba_id: config['business_account_id'].presence }
  end

  def reportable?(inbox)
    credentials = self.for(inbox)
    credentials[:access_token].present? && credentials[:waba_id].present?
  end
end
