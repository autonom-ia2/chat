# Conexão IMAP da caixa de e-mail para o "lido" sincronizado (#1870), usada pelo job que escreve o \Seen no servidor.
# - Lock com dono na mesma chave da importação (ConversaCanal::LockDaCaixa): uma conexão por caixa de cada vez, e a
#   escrita daqui nunca cruza com a leitura do \Seen da importação. O token OAuth é renovado só dentro do lock (a
#   Microsoft troca o refresh_token a cada renovação). O bloco recebe a conexão e o lock (para renovar entre passos).
# - Credencial que não serve não chega ao servidor: caixa marcada para reautorizar e OAuth sem access_token ou sem
#   refresh_token viram CredencialRecusada; o job registra e descarta. O painel não conta erro de autorização na caixa
#   (isso dispara o e-mail de reautorização aos donos): quem decide a reautorização é a importação.
# - Recusa na autenticação (NO/BAD no LOGIN ou AUTHENTICATE, mecanismo inválido, OAuth 4xx) também vira
#   CredencialRecusada. Ver ConversaCanal::LidoNaImportacaoDoEmail#com_a_conexao.
# - Usa o serviço de importação do provedor (Google e Microsoft por OAuth, ou senha): mesma autenticação e mesmo SELECT do
#   INBOX. A escolha do serviço é a mesma do Inboxes::FetchImapEmailsJob.
module ConversaCanal::ConexaoDoEmail
  class CredencialRecusada < StandardError; end

  module_function

  def abrir(channel)
    conferir_credencial!(channel)
    ConversaCanal::LockDaCaixa.com_lock(channel.inbox) do |lock|
      servico(channel).com_a_conexao { |imap| yield imap, lock }
    end
  end

  def conferir_credencial!(channel)
    raise CredencialRecusada, 'reauthorization_required' if channel.reauthorization_required?
    return unless channel.microsoft? || channel.google?

    config = channel.provider_config.to_h
    raise CredencialRecusada, 'access_token_blank' if config['access_token'].blank?
    raise CredencialRecusada, 'refresh_token_blank' if config['refresh_token'].blank?
  end

  def servico(channel)
    if channel.microsoft?
      Imap::MicrosoftFetchEmailService.new(channel: channel)
    elsif channel.google?
      Imap::GoogleFetchEmailService.new(channel: channel)
    else
      Imap::FetchEmailService.new(channel: channel)
    end
  end

  # UIDVALIDITY do INBOX selecionado. Na net-imap 0.6.4.1 ela chega como resposta não marcada do SELECT
  # ("* OK [UIDVALIDITY n]") e fica em #responses (o SELECT limpa as anteriores). Pode faltar (nil) em servidor fora do RFC.
  def uidvalidity(imap)
    imap.responses('UIDVALIDITY', &:last)
  end
end
