module Waha
  # Orquestra, em poucas chamadas, tudo o que hoje é feito na mão: cria a caixa
  # (canal API igual ao padrão), cria a sessão no motor externo e liga o conector
  # de mensagens — deixando só o passo humano de ler o QR.
  class InboxProvisioner
    class Error < StandardError; end

    Result = Struct.new(:inbox, :session, :app_id, :phone_numbers_app_id, keyword_init: true)

    # Celular BR no formato 55 + DDD(2) + 9 dígitos (ex.: 5511987654321) = 13 dígitos.
    PHONE_RE = /\A55\d{11}\z/

    def initialize(account:, phone:, api_access_token:, display_name: nil, ai_agent: false,
                   client: Waha::Client.new, config: Waha::Config)
      @account = account
      @phone = normalize_phone(phone)
      @api_access_token = api_access_token.to_s
      @display_name = display_name.to_s.strip
      @ai_agent = ActiveModel::Type::Boolean.new.cast(ai_agent)
      @client = client
      @config = config
    end

    def perform
      validate_request!
      app_id = "app_#{SecureRandom.hex(16)}"
      phone_numbers_app_id = "br_#{SecureRandom.hex(16)}"
      inbox = create_local_inbox(app_id, phone_numbers_app_id)

      provision_remote(inbox, app_id, phone_numbers_app_id)

      Result.new(
        inbox: inbox,
        session: @phone,
        app_id: app_id,
        phone_numbers_app_id: phone_numbers_app_id
      )
    end

    private

    def validate_request!
      raise Error, 'integration_not_configured' unless @config.enabled?
      raise Error, 'invalid_phone' unless @phone.match?(PHONE_RE)
      raise Error, 'account_token_missing' if @api_access_token.blank?
    end

    def create_local_inbox(app_id, phone_numbers_app_id)
      callback = @config.callback_url(@phone, app_id)
      ActiveRecord::Base.transaction do
        create_inbox(callback, app_id, phone_numbers_app_id)
      end
    end

    def provision_remote(inbox, app_id, phone_numbers_app_id)
      @client.create_session(
        @phone,
        start: true,
        config: { ignore: @config.session_ignore },
        apps: session_apps(inbox, app_id, phone_numbers_app_id)
      )
    rescue StandardError => e
      cleanup_inbox(inbox)
      cleanup_remote(app_id, phone_numbers_app_id)
      Rails.logger.error("[Waha] provisioning failed account=#{@account.id}: #{e.class}")
      raise Error, 'remote_setup_failed'
    end

    def create_inbox(callback, app_id, phone_numbers_app_id)
      channel = @account.api_channels.create!(
        webhook_url: callback,
        additional_attributes: {
          'provider' => 'waha',
          'session' => @phone,
          'app_id' => app_id,
          'phone_numbers_app_id' => phone_numbers_app_id,
          'account_token_owner_user_id' => Current.user&.id,
          'kind' => @ai_agent ? 'ai' : 'human',
          # Já nasce marcada como caixa de campanha WhatsApp API — uma caixa WAHA É, por definição,
          # uma caixa de WhatsApp API; sem isto o seletor de campanha (filtra por campaign_channel_type)
          # nunca a enxerga e o disparo "one-click" fica inacessível.
          'campaign_channel_type' => Channel::Api::WHATSAPP_API_CAMPAIGN_CHANNEL_TYPE,
          'whatsapp_api_provider' => Channel::Api::WHATSAPP_API_CAMPAIGN_PROVIDER
        }
      )
      @account.inboxes.create!(
        name: inbox_display_name,
        channel: channel,
        lock_to_single_conversation: true
      )
    end

    # IA: nome = telefone (automação depende). Humano: nome livre, telefone na sessão.
    def inbox_display_name
      return @phone if @ai_agent
      @display_name.presence || @phone
    end

    def session_apps(inbox, app_id, phone_numbers_app_id)
      [
        Waha::BrazilianPhoneNumbers.app_payload(session: @phone, app_id: phone_numbers_app_id),
        {
          id: app_id,
          session: @phone,
          app: 'chatwoot',
          enabled: true,
          config: app_config(inbox)
        }
      ]
    end

    def app_config(inbox)
      {
        url: @config.chatwoot_base_url,
        accountId: @account.id,
        accountToken: @api_access_token,
        inboxId: inbox.id,
        inboxIdentifier: inbox.channel.identifier,
        locale: 'pt-BR',
        linkPreview: 'OFF',
        groups: 'OFF',
        templates: {},
        commands: { server: true, queue: true },
        conversations: {
          markAsRead: true,
          syncMessageStatus: true,
          sort: @config.conversation_sort,
          status: nil,
          outgoing: 'message'
        }
      }
    end

    def normalize_phone(phone)
      phone.to_s.gsub(/\D/, '')
    end

    def cleanup_inbox(inbox)
      inbox&.destroy
    rescue StandardError
      nil
    end

    def cleanup_remote(*app_ids)
      app_ids.compact.each do |app_id|
        @client.delete_app(app_id)
      rescue StandardError
        nil
      end
    ensure
      begin
        @client.delete_session(@phone)
      rescue StandardError
        nil
      end
    end
  end
end
