module Waha
  # Orquestra, em poucas chamadas, tudo o que hoje é feito na mão: cria a caixa
  # (canal API igual ao padrão), cria a sessão no motor externo e liga o conector
  # de mensagens — deixando só o passo humano de ler o QR.
  #
  # Idempotente por conta e número (#2478): a conta que já tem caixa com o número recebe a mesma caixa de volta, e a
  # sessão que sobrou no motor sem caixa é reaproveitada em vez de travar a criação.
  class InboxProvisioner
    class Error < StandardError; end

    Result = Struct.new(:inbox, :session, :app_id, :phone_numbers_app_id, keyword_init: true)

    # Celular BR no formato 55 + DDD(2) + 9 dígitos (ex.: 5511987654321) = 13 dígitos.
    PHONE_RE = /\A55\d{11}\z/

    # Sessão parada no motor: depois de trocar os apps, precisa ligar para mostrar o QR.
    START_AGAIN_STATUSES = %w[STOPPED FAILED].freeze

    def initialize(account:, phone:, api_access_token:, display_name: nil, ai_agent: false,
                   client: Waha::Client.new, config: Waha::Config, proxy_assigner: WhatsappProxy::Assigner.new)
      @account = account
      @phone = normalize_phone(phone)
      @api_access_token = api_access_token.to_s
      @display_name = display_name.to_s.strip
      @ai_agent = ActiveModel::Type::Boolean.new.cast(ai_agent)
      @client = client
      @config = config
      @proxy_assigner = proxy_assigner
    end

    def perform
      validate_request!
      app_id = "app_#{SecureRandom.hex(16)}"
      phone_numbers_app_id = "br_#{SecureRandom.hex(16)}"
      inbox, created = find_or_create_local_inbox(app_id, phone_numbers_app_id)
      return result_for(inbox) unless created

      provision_remote(inbox, app_id, phone_numbers_app_id)
      result_for(inbox)
    end

    private

    def validate_request!
      raise Error, 'integration_not_configured' unless @config.enabled?
      raise Error, 'invalid_phone' unless @phone.match?(PHONE_RE)
      raise Error, 'account_token_missing' if @api_access_token.blank?
    end

    # A trava pelo número segura dois cliques ao mesmo tempo (e duas contas com o mesmo número): o segundo espera o
    # primeiro gravar a caixa e recebe a mesma.
    def find_or_create_local_inbox(app_id, phone_numbers_app_id)
      ActiveRecord::Base.transaction do
        lock_phone!
        existing = waha_channels.find_by(account_id: @account.id)&.inbox
        next [existing, false] if existing
        raise Error, 'phone_in_use_elsewhere' if waha_channels.where.not(account_id: @account.id).exists?

        [create_inbox(@config.callback_url(@phone, app_id), app_id, phone_numbers_app_id), true]
      end
    end

    def lock_phone!
      sql = ActiveRecord::Base.sanitize_sql_array(['SELECT pg_advisory_xact_lock(hashtextextended(?, 0))', "waha_inbox:#{@phone}"])
      ActiveRecord::Base.connection.execute(sql)
    end

    def waha_channels
      Channel::Api.where("additional_attributes ->> 'provider' = 'waha'")
                  .where("additional_attributes ->> 'session' = ?", @phone)
    end

    def result_for(inbox)
      attrs = inbox.channel.additional_attributes.to_h
      Result.new(inbox: inbox, session: @phone, app_id: attrs['app_id'], phone_numbers_app_id: attrs['phone_numbers_app_id'])
    end

    # A sessão já nasce com o IP próprio da Webshare (#1516). Sem IP disponível, nasce sem proxy em vez de travar.
    def provision_remote(inbox, app_id, phone_numbers_app_id)
      proxy = @proxy_assigner.for(@phone)
      config = { ignore: @config.session_ignore, proxy: proxy&.to_session_config }.compact
      setup_session(config, session_apps(inbox, app_id, phone_numbers_app_id))
      proxy ? @proxy_assigner.mark_applied!(@phone, proxy) : @proxy_assigner.mark_pending!(@phone)
    rescue StandardError => e
      rollback(inbox, app_id, phone_numbers_app_id)
      log_failure(e)
      raise Error, error_code_for(e)
    end

    # Sessão que sobrou no motor sem caixa (nenhuma conta tem caixa com ela, conferido sob a trava): reaproveita.
    # `update_session` com `apps` troca o conjunto de apps da sessão pelo informado (o mesmo contrato que
    # Waha::ExistingInboxMigrationExecutor confere depois da troca), então o conector antigo, que apontava para uma
    # caixa que não existe mais, sai junto.
    def setup_session(config, apps)
      remote = existing_session
      if remote
        @remote_state = :reused
        @client.update_session(@phone, config: config, apps: apps)
        @client.start_session(@phone) if START_AGAIN_STATUSES.include?(remote['status'])
      else
        @remote_state = :created
        @client.create_session(@phone, start: true, config: config, apps: apps)
      end
    end

    def existing_session
      @client.get_session(@phone)
    rescue Waha::Client::NotFound
      nil
    end

    # Só apaga a sessão se esta tentativa a criou. Sessão reaproveitada fica; saem só os apps postos agora.
    def rollback(inbox, app_id, phone_numbers_app_id)
      cleanup_inbox(inbox)
      [app_id, phone_numbers_app_id].each { |id| quietly { @client.delete_app(id) } } if @remote_state
      quietly { @client.delete_session(@phone) } if @remote_state == :created
      quietly { @proxy_assigner.release!(@phone) }
    end

    def error_code_for(error)
      engine_unreachable?(error) ? 'engine_unavailable' : 'remote_setup_failed'
    end

    # Sem resposta do motor (tempo esgotado, conexão recusada): status nil. Resposta ilegível não é motor fora do ar.
    def engine_unreachable?(error)
      return true if error.is_a?(Waha::Client::Timeout)

      error.is_a?(Waha::Client::Error) && !error.is_a?(Waha::Client::InvalidResponse) && error.status.nil?
    end

    # A mensagem do cliente traz método, rota, status e o começo da resposta do motor (já sem a senha do proxy).
    # O token da conta vai no corpo do pedido; se o motor o devolver, não chega ao log.
    def log_failure(error)
      message = error.message.to_s.gsub(@api_access_token, '[FILTERED]')
      Rails.logger.error("[Waha] provisioning failed account=#{@account.id} session=#{@phone}: #{error.class}: #{message}")
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
          sort: Waha::Config.conversation_sort,
          status: nil,
          outgoing: 'message'
        }
      }
    end

    def normalize_phone(phone)
      phone.to_s.gsub(/\D/, '')
    end

    # O lado remoto é desfeito aqui, não no destroy do canal: ele apagaria a sessão mesmo quando ela foi reaproveitada.
    def cleanup_inbox(inbox)
      return unless inbox

      inbox.channel&.skip_waha_remote_cleanup = true
      inbox.destroy
    rescue StandardError
      nil
    end

    # Desfazer é melhor esforço: uma limpeza que falha não impede as outras nem esconde o erro original.
    def quietly
      yield
    rescue StandardError
      nil
    end
  end
end
