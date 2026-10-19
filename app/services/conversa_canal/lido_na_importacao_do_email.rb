# #1870 — Prepend em Imap::BaseFetchEmailService (Google, Microsoft e senha passam por ele).
# - Depois da importação de cada minuto, na mesma conexão e antes do logout, traz do servidor o \Seen dos e-mails já
#   importados (ConversaCanal::EmailLidoDoServidor). Roda dentro do lock da caixa que o Inboxes::FetchImapEmailsJob já
#   segura (EMAIL_MESSAGE_MUTEX), o mesmo da escrita (ConversaCanal::LockDaCaixa).
#   Fica num FETCH à parte porque o FETCH da importação olha a janela do `interval` (1 dia) e descarta na hora os e-mails
#   já importados, que são justamente os que interessam aqui.
# - Caixa que não sincroniza (flag desligada, sem IMAP): conexão, fechamento e erros exatamente como no Chatwoot (super).
# - Caixa que sincroniza:
#   - falha ao trazer o lido vira registro (só a classe, ConversaCanal::FalhaDoEmailLido) e nunca impede a importação de
#     devolver os e-mails do minuto: o fechamento também não estoura (socket quebrado vira disconnect);
#   - autenticação ou SELECT recusados fecham o socket antes de relançar o erro.
# - `com_a_conexao` empresta a conexão autenticada ao job que escreve o \Seen no servidor. Recusa na AUTENTICAÇÃO vira
#   ConversaCanal::ConexaoDoEmail::CredencialRecusada (o job descarta): NO/BAD do LOGIN/AUTHENTICATE, mecanismo que a
#   net-imap não conhece (conferido ANTES do AUTHENTICATE no registro dela, Net::IMAP::SASL.authenticators.mechanism?;
#   um ArgumentError de dentro da autenticação, como senha nil, é bug e não é recusa), StandardError puro do
#   Imap::Authentication, refresh_token ausente (RuntimeError puro do
#   BaseRefreshOauthTokenService) e OAuth 4xx (invalid_grant etc.). BYE, OAuth 5xx, rede e timeout (Timeout::Error,
#   Net::OpenTimeout, SocketError) e qualquer erro do SELECT saem como são: o job tenta de novo.
module ConversaCanal::LidoNaImportacaoDoEmail
  ERROS_AO_FECHAR = [IOError, OpenSSL::SSL::SSLError, SystemCallError, Net::IMAP::Error, Timeout::Error].freeze
  # ArgumentError, como o da net-imap para mecanismo desconhecido: quem chamava o Chatwoot continua vendo a mesma família.
  class MecanismoDesconhecido < ArgumentError; end

  RECUSAS_NA_AUTENTICACAO = [Net::IMAP::NoResponseError, Net::IMAP::BadResponseError, MecanismoDesconhecido].freeze
  RECUSA_DO_OAUTH = (400..499)

  # O ensure não troca a exceção do bloco por uma do fechamento.
  def com_a_conexao
    yield conectar_para_o_lido
  ensure
    fechar_sem_estourar
  end

  private

  def lido_sincronizado?
    return @lido_sincronizado if defined?(@lido_sincronizado)

    @lido_sincronizado = ConversaCanal::EmailLido.sincroniza?(channel.inbox)
  end

  def fetch_mail_for_channel
    emails = super
    trazer_lidos_do_servidor
    emails
  end

  def trazer_lidos_do_servidor
    return unless lido_sincronizado?

    ConversaCanal::EmailLidoDoServidor.new(channel: channel, imap: imap_client).sincronizar
  rescue StandardError => e
    inbox_id = channel.inbox.id
    ConversaCanal::FalhaDoEmailLido.registrar(e, account: channel.account, inbox_id: inbox_id, onde: "servidor -> painel inbox=#{inbox_id}")
  end

  def conectar_para_o_lido
    imap_client
  rescue StandardError => e
    raise ConversaCanal::ConexaoDoEmail::CredencialRecusada, e.class.name if @fase_da_conexao == :autenticacao && recusa?(e)

    raise
  end

  # RuntimeError/StandardError por classe exata: nunca uma subclasse como Timeout::Error.
  def recusa?(error)
    case error
    when *RECUSAS_NA_AUTENTICACAO then true
    when OAuth2::Error then RECUSA_DO_OAUTH.cover?(error.response&.status.to_i)
    else [RuntimeError, StandardError].include?(error.class)
    end
  end

  def build_imap_client
    return super unless lido_sincronizado?

    imap = Net::IMAP.new(channel.imap_address, port: channel.imap_port, ssl: channel.imap_enable_ssl)
    begin
      @fase_da_conexao = :autenticacao
      conferir_mecanismo!
      Imap::Authentication.authenticate!(imap, authentication_type, channel.imap_login, imap_password)
      @fase_da_conexao = :select
      imap.select('INBOX')
    rescue StandardError
      desconectar(imap)
      raise
    end
    Rails.logger.info "[IMAP::FETCH_EMAIL_SERVICE] IMAP connection established for #{channel.email}"
    imap
  end

  # O mesmo nome que o Imap::Authentication manda ao AUTHENTICATE; 'login' vai pelo comando LOGIN, sem SASL.
  def conferir_mecanismo!
    mecanismo = Imap::Authentication.normalize(authentication_type).to_s
    return if mecanismo.casecmp?('login') || Net::IMAP::SASL.authenticators.mechanism?(mecanismo)

    raise MecanismoDesconhecido, 'mecanismo de autenticação desconhecido'
  end

  def terminate_imap_connection
    return super if @imap_client.nil? || !lido_sincronizado?

    sair_da_conexao
  end

  def sair_da_conexao
    @imap_client.logout
  rescue *ERROS_AO_FECHAR => e
    Rails.logger.info("Logout failed for #{channel.email} - #{e.class}.")
    desconectar(@imap_client)
  end

  def fechar_sem_estourar
    terminate_imap_connection if @imap_client
  rescue StandardError => e
    Rails.logger.info("[conversa_canal][email_lido] fechar conexão falhou inbox=#{channel.inbox.id} #{e.class}")
  end

  def desconectar(imap)
    imap&.disconnect
  rescue StandardError
    nil
  end
end
