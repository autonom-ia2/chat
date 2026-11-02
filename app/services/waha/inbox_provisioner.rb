module Waha
  # Orquestra, em poucas chamadas, tudo o que hoje é feito na mão: cria a caixa
  # (canal API igual ao padrão), cria a sessão no motor externo e liga o conector
  # de mensagens — deixando só o passo humano de ler o QR.
  #
  # Idempotente por conta e número (#2478): a conta que já tem caixa com o número recebe a mesma caixa de volta, e a
  # sessão sem caixa que é provadamente nossa e desta conta é reaproveitada em vez de travar a criação.
  class InboxProvisioner
    class Error < StandardError; end

    Result = Struct.new(:inbox, :session, :app_id, :phone_numbers_app_id, keyword_init: true)

    # Celular BR no formato 55 + DDD(2) + 9 dígitos (ex.: 5511987654321) = 13 dígitos.
    PHONE_RE = /\A55\d{11}\z/

    # Sessão parada no motor: depois de trocar os apps, precisa ligar para mostrar o QR.
    START_AGAIN_STATUSES = %w[STOPPED FAILED].freeze
    # Resposta do gateway na frente do motor: o motor não respondeu.
    NO_ANSWER_STATUSES = [502, 503, 504].freeze
    # Caixa gravada cujo lado remoto ainda não terminou. Sobra quando o desfazer não conseguiu apagá-la; o próximo
    # pedido termina o lado remoto dela em vez de responder com uma caixa sem sessão.
    PENDING_KEY = 'provisioning_pending'.freeze

    def initialize(account:, phone:, api_access_token:, display_name: nil, ai_agent: false,
                   client: Waha::Client.new, config: Waha::Config, proxy_assigner: WhatsappProxy::Assigner.new)
      @account = account
      @phone = normalize_phone(phone)
      @api_access_token = api_access_token.to_s
      @display_name = display_name.to_s.strip
      @ai_agent = ActiveModel::Type::Boolean.new.cast(ai_agent)
      @client = client
      @config = config
      @proxy = ProxyReservation.new(proxy_assigner, @phone)
    end

    def perform
      validate_request!
      with_phone_lock do
        inbox = find_or_create_local_inbox
        if pending?(inbox)
          provision_remote(inbox)
          finish!(inbox)
        elsif session_missing?
          # Caixa pronta (inclusive de antes de PENDING_KEY) cuja sessão não está no motor: refaz o lado remoto. Se falhar,
          # a caixa fica, porque já existia antes deste pedido.
          provision_remote(inbox, keep_inbox: true)
        end
        result_for(inbox)
      end
    end

    private

    def validate_request!
      raise Error, 'integration_not_configured' unless @config.enabled?
      raise Error, 'invalid_phone' unless @phone.match?(PHONE_RE)
      raise Error, 'account_token_missing' if @api_access_token.blank?
    end

    # Trava pelo número do começo ao fim, lado remoto incluído: o segundo clique (ou outra conta com o mesmo número)
    # espera o primeiro terminar e recebe a caixa pronta, ou cria do zero se o primeiro desfez tudo. Trava de sessão do
    # Postgres, na mesma conexão do pedido, para não segurar transação aberta durante as chamadas ao motor.
    def with_phone_lock
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        key = connection.quote("waha_inbox:#{@phone}")
        connection.execute("SELECT pg_advisory_lock(hashtextextended(#{key}, 0))")
        begin
          yield
        ensure
          connection.select_value("SELECT pg_advisory_unlock(hashtextextended(#{key}, 0))")
        end
      end
    end

    def find_or_create_local_inbox
      existing = waha_channels.find_by(account_id: @account.id)&.inbox
      return existing if existing
      raise Error, 'phone_in_use_elsewhere' if waha_channels.where.not(account_id: @account.id).exists?

      app_id = "app_#{SecureRandom.hex(16)}"
      ActiveRecord::Base.transaction do
        create_inbox(@config.callback_url(@phone, app_id), app_id, "br_#{SecureRandom.hex(16)}")
      end
    end

    # Só canais com caixa: canal solto não é dono do número.
    def waha_channels
      Channel::Api.joins(:inbox)
                  .where("channel_api.additional_attributes ->> 'provider' = 'waha'")
                  .where("channel_api.additional_attributes ->> 'session' = ?", @phone)
    end

    def pending?(inbox)
      inbox.channel.additional_attributes.to_h[PENDING_KEY].present?
    end

    def finish!(inbox)
      inbox.channel.update!(additional_attributes: inbox.channel.additional_attributes.to_h.except(PENDING_KEY))
    end

    def result_for(inbox)
      attrs = inbox.channel.additional_attributes.to_h
      Result.new(inbox: inbox, session: @phone, app_id: attrs['app_id'], phone_numbers_app_id: attrs['phone_numbers_app_id'])
    end

    # A sessão já nasce com o IP próprio da Webshare (#1516). Sem IP disponível, nasce sem proxy em vez de travar.
    def provision_remote(inbox, keep_inbox: false)
      app_ids = inbox.channel.additional_attributes.to_h.values_at('app_id', 'phone_numbers_app_id')
      remote = existing_session
      raise Error, 'phone_in_use_elsewhere' if remote && !ours?

      @proxy.take
      setup_session(remote, SessionApps.for(inbox: inbox, account: @account, token: @api_access_token, config: @config))
      @proxy.confirm!
    rescue Error
      rollback(inbox, app_ids, keep_inbox)
      raise
    rescue StandardError => e
      rollback(inbox, app_ids, keep_inbox)
      log_failure(e)
      raise Error, error_code_for(e)
    end

    # O motor é compartilhado e tem sessões sem caixa de propósito (número pessoal, outro sistema). Só se reaproveita a
    # sessão provadamente nossa e desta conta, em qualquer estado; o resto é número em uso fora daqui.
    def ours?
      SessionApps.ours?(@client.list_apps(@phone), account: @account, config: @config)
    end

    # Sessão nossa e desta conta que sobrou no motor sem caixa (nenhuma conta tem caixa com ela, conferido sob a trava).
    # `update_session` troca a config inteira e o conjunto de apps da sessão pelo informado (o mesmo contrato que
    # Waha::ExistingInboxMigrationExecutor confere depois da troca), então o conector antigo, que apontava para uma
    # caixa que não existe mais, sai junto. Sem IP novo, a sessão fica com o proxy que já tinha.
    def setup_session(remote, apps)
      config = { ignore: @config.session_ignore, proxy: @proxy.proxy&.to_session_config || remote&.dig('config', 'proxy') }.compact
      return create_session(config, apps) unless remote

      @remote_state = :reused
      @client.update_session(@phone, config: config, apps: apps)
      @client.start_session(@phone) if START_AGAIN_STATUSES.include?(remote['status'])
    end

    # Criada = o motor respondeu 2xx, ou não respondeu (pode ter criado). Recusa com status (4xx) não criou nada.
    def create_session(config, apps)
      @client.create_session(@phone, start: true, config: config, apps: apps)
      @remote_state = :created
    rescue Waha::Client::Error => e
      @remote_state = :created if no_answer?(e)
      raise
    end

    def existing_session
      @client.get_session(@phone)
    rescue Waha::Client::NotFound
      nil
    end

    # Motor sem resposta aqui não vira 200 com uma caixa que pode estar sem sessão: a pessoa tenta de novo depois.
    def session_missing?
      existing_session.nil?
    rescue Waha::Client::Error => e
      log_failure(e)
      raise Error, error_code_for(e)
    end

    # Só apaga a sessão se esta tentativa a criou. Sessão reaproveitada fica; saem só os apps postos agora.
    def rollback(inbox, app_ids, keep_inbox)
      cleanup_inbox(inbox) unless keep_inbox
      app_ids.compact.each { |id| quietly { @client.delete_app(id) } } if @remote_state
      quietly { @client.delete_session(@phone) } if @remote_state == :created
      @proxy.undo!(session_removed: @remote_state == :created)
    end

    def error_code_for(error)
      engine_unreachable?(error) ? 'engine_unavailable' : 'remote_setup_failed'
    end

    # Resposta ilegível (InvalidResponse) não é motor fora do ar: o motor respondeu.
    def engine_unreachable?(error)
      error.is_a?(Waha::Client::Error) && !error.is_a?(Waha::Client::InvalidResponse) && no_answer?(error)
    end

    def no_answer?(error)
      error.status.nil? || NO_ANSWER_STATUSES.include?(error.status)
    end

    # A mensagem do cliente traz método, rota, status e o começo da resposta do motor (o cliente já tira a credencial do
    # proxy enviado). O token da conta vai no corpo do pedido; se o motor o devolver, não chega a esta linha. O número
    # vai mascarado só nesta linha: o Assigner de proxy tem log próprio, com o número inteiro.
    def log_failure(error)
      masked = "***#{@phone.last(4)}"
      message = error.message.to_s.gsub(@api_access_token, '[FILTERED]').gsub(@phone, masked)
      Rails.logger.error("[Waha] provisioning failed account=#{@account.id} session=#{masked}: #{error.class}: #{message}")
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
          'whatsapp_api_provider' => Channel::Api::WHATSAPP_API_CAMPAIGN_PROVIDER,
          PENDING_KEY => true
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

    def normalize_phone(phone)
      phone.to_s.gsub(/\D/, '')
    end

    # O lado remoto é desfeito em `rollback`, não no destroy do canal: ele apagaria a sessão mesmo quando ela foi
    # reaproveitada. A flag vai no objeto do canal que `inbox.destroy!` destrói (belongs_to dependent: :destroy).
    # Se a caixa não sai, ela fica com PENDING_KEY e o próximo pedido termina o lado remoto dela.
    def cleanup_inbox(inbox)
      inbox.channel.skip_waha_remote_cleanup = true
      inbox.destroy!
    rescue StandardError => e
      Rails.logger.error("[Waha] rollback kept inbox=#{inbox.id} account=#{@account.id}: #{e.class}")
    end

    # Desfazer é melhor esforço: uma limpeza que falha não impede as outras nem esconde o erro original.
    def quietly
      yield
    rescue StandardError
      nil
    end
  end
end
