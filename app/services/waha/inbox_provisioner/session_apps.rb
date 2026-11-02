# Os dois apps da sessão de uma caixa WAHA: resolução de número brasileiro e o conector de mensagens apontando para a
# caixa. Saiu do InboxProvisioner sem mudança de conteúdo (#2478).
class Waha::InboxProvisioner::SessionApps
  def self.for(inbox:, account:, token:, config:)
    attrs = inbox.channel.additional_attributes.to_h
    new(inbox, account, token, config).payload(attrs['session'], attrs['app_id'], attrs['phone_numbers_app_id'])
  end

  def initialize(inbox, account, token, config)
    @inbox = inbox
    @account = account
    @token = token
    @config = config
  end

  def payload(session, app_id, phone_numbers_app_id)
    [
      Waha::BrazilianPhoneNumbers.app_payload(session: session, app_id: phone_numbers_app_id),
      { id: app_id, session: session, app: 'chatwoot', enabled: true, config: app_config }
    ]
  end

  private

  def app_config
    {
      url: @config.chatwoot_base_url,
      accountId: @account.id,
      accountToken: @token,
      inboxId: @inbox.id,
      inboxIdentifier: @inbox.channel.identifier,
      locale: 'pt-BR',
      linkPreview: 'OFF',
      groups: 'OFF',
      templates: {},
      commands: { server: true, queue: true },
      conversations: {
        markAsRead: true,
        syncMessageStatus: true,
        sort: Waha::Config.conversation_sort,
        status: nil,
        outgoing: 'message'
      }
    }
  end
end
