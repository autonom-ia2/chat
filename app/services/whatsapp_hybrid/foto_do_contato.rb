# Foto de perfil do contato na caixa híbrida (#1934). A Cloud não manda a foto e não tem endpoint para buscar; a sessão
# WAHA da própria caixa (o mesmo número) vê a foto como o WhatsApp do celular vê. Decisão do Rodrigo (20/10): buscar
# só no híbrido; a Cloud pura fica sem foto.
# - Gatilho (`after_commit` de Message): mensagem recebida numa caixa híbrida, de contato sem foto, com a flag ligada.
#   O histórico importado pela coexistência (`history_import`) não dispara, como os outros efeitos da Message.
# - A busca (WhatsappHybrid::FotoDoContatoJob): só com a sessão em uso pelo Híbrido (`routable?`: conectada, no mesmo
#   número, roteamento ligado, risco aceito, não pausada) e com as chaves gerais do Híbrido ligadas. Desligar o
#   WhatsApp API da caixa ou da plataforma desliga também a busca da foto.
# - Por contato: 1 tentativa a cada 7 dias (marca no Redis, gravada antes de consultar o motor). Achou:
#   Avatar::AvatarFromUrlJob baixa o arquivo (a URL do WhatsApp expira). Sem foto, escondida pela privacidade ou sem
#   telefone: 30 dias, sem aviso nem erro.
# - Por sessão: 1 consulta a cada 15 s e 300 por dia. Sem vaga, desiste sem marcar o contato: a próxima mensagem dele
#   tenta de novo. Uma rajada (campanha recebendo respostas) não vira rajada no motor.
# - Erro do MOTOR (sem resposta, conexão, limite de consultas 429, 5xx) pausa as buscas da sessão por 1 hora e devolve o
#   contato. Qualquer outro erro (4xx do contato, resposta fora do formato, Redis) só adia aquele contato 1 dia: um
#   contato problemático não para a foto dos outros.
class WhatsappHybrid::FotoDoContato
  FLAG = 'hibrido_foto_do_contato'.freeze
  INTERVALO = 7.days
  SEM_FOTO = 30.days
  ADIADO = 1.day
  PAUSA_DA_SESSAO = 1.hour
  RITMO = 15.seconds
  TETO_DIARIO = 300
  TIMEOUT = 10
  LIMITE_DE_CONSULTAS = 429
  ERROS_DE_REDE = [Timeout::Error, SocketError, SystemCallError, IOError, EOFError, OpenSSL::SSL::SSLError,
                   Net::ProtocolError].freeze

  def self.after_commit(message)
    return unless buscar_para?(message)

    WhatsappHybrid::FotoDoContatoJob.perform_later(message.sender_id, message.inbox_id)
  rescue StandardError => e
    Rails.logger.error("[whatsapp_hybrid] foto do contato (gatilho) #{e.class}")
  end

  # Do mais barato ao mais caro: a foto já anexada é a única consulta ao banco.
  def self.buscar_para?(message)
    message.incoming? && message.sender_type == 'Contact' && !message.content_attributes.to_h['history_import'] &&
      message.account.feature_enabled?(FLAG) && WhatsappHybrid::Config.hybrid_inbox?(message.inbox_id) &&
      !::Redis::Alfred.exists?(chave_do_contato(message.sender_id)) && !message.sender.avatar.attached?
  end

  def self.chave_do_contato(contact_id)
    "whatsapp_hybrid:foto_do_contato:#{contact_id}"
  end

  def self.chave_da_sessao(session_name)
    "whatsapp_hybrid:foto_do_contato:pausa:#{session_name}"
  end

  def self.chave_do_dia(session_name)
    "whatsapp_hybrid:foto_do_contato:dia:#{session_name}:#{Time.current.utc.to_date}"
  end

  # A sessão em uso pelo Híbrido, com as chaves gerais ligadas e sem pausa da busca de foto.
  def self.sessao_pronta?(connection)
    WhatsappHybrid::Config.routing_enabled? && WhatsappHybrid::Config.account_allowed?(connection.account_id) &&
      connection.routable? && !::Redis::Alfred.exists?(chave_da_sessao(connection.session_name))
  end

  def self.consultas_hoje(session_name)
    ::Redis::Alfred.get(chave_do_dia(session_name)).to_i
  end

  def initialize(contact:, connection:, client: Waha::Client.new)
    @contact = contact
    @connection = connection
    @client = client
  end

  def perform
    return unless sessao_pronta? && !@contact.avatar.attached?
    # SET NX: dois jobs do mesmo contato (mensagens seguidas) não consultam o motor duas vezes.
    return unless ::Redis::Alfred.set(self.class.chave_do_contato(@contact.id), 1, nx: true, ex: INTERVALO.to_i)

    consultar
  rescue StandardError => e
    erro_do_motor?(e) ? pausar_a_sessao(e) : adiar_o_contato(e)
  end

  private

  def consultar
    return marcar(SEM_FOTO) unless contact_id
    return devolver_o_contato unless vaga_na_sessao?

    url = url_da_foto
    url ? Avatar::AvatarFromUrlJob.perform_later(@contact, url) : marcar(SEM_FOTO)
  end

  def sessao_pronta?
    self.class.sessao_pronta?(@connection)
  end

  # 1 consulta a cada RITMO por sessão (SET NX) e no máximo TETO_DIARIO por dia. O contador do dia nasce com prazo
  # (SET NX EX antes do INCR): nunca fica sem expirar.
  def vaga_na_sessao?
    sessao = @connection.session_name
    return false unless ::Redis::Alfred.set("whatsapp_hybrid:foto_do_contato:ritmo:#{sessao}", 1, nx: true, ex: RITMO.to_i)

    chave_do_dia = self.class.chave_do_dia(sessao)
    ::Redis::Alfred.set(chave_do_dia, 0, nx: true, ex: 1.day.to_i)
    ::Redis::Alfred.incr(chave_do_dia) <= TETO_DIARIO
  end

  # Resposta que não é o formato esperado não é "sem foto": o contato fica adiado (ver o rescue do perform).
  def url_da_foto
    resposta = @client.profile_picture(session: @connection.session_name, contact_id: contact_id, timeout: TIMEOUT)
    raise Waha::Client::InvalidResponse, 'foto do contato: resposta sem objeto' unless resposta.is_a?(Hash)

    resposta['profilePictureURL'].presence
  end

  # Sem resposta (status nil: conexão, timeout), limite de consultas ou erro do servidor do motor.
  def erro_do_motor?(error)
    return true if ERROS_DE_REDE.any? { |classe| error.is_a?(classe) }
    return false unless error.is_a?(Waha::Client::Error) && !error.is_a?(Waha::Client::InvalidResponse)

    error.status.nil? || error.status == LIMITE_DE_CONSULTAS || error.status >= 500
  end

  def pausar_a_sessao(error)
    devolver_o_contato
    ::Redis::Alfred.setex(self.class.chave_da_sessao(@connection.session_name), 1, PAUSA_DA_SESSAO.to_i)
    Rails.logger.warn("[whatsapp_hybrid] foto do contato: busca pausada na sessão inbox=#{@connection.inbox_id} #{detalhe(error)}")
  end

  def adiar_o_contato(error)
    marcar(ADIADO)
    Rails.logger.info("[whatsapp_hybrid] foto do contato: contato adiado inbox=#{@connection.inbox_id} #{detalhe(error)}")
  rescue StandardError
    nil
  end

  def detalhe(error)
    "status=#{error.respond_to?(:status) ? error.status.inspect : '-'} #{error.class}"
  end

  def marcar(prazo)
    ::Redis::Alfred.setex(self.class.chave_do_contato(@contact.id), 1, prazo.to_i)
  end

  def devolver_o_contato
    ::Redis::Alfred.delete(self.class.chave_do_contato(@contact.id))
  end

  # O número com que o contato conversa: na Cloud, o `wa_id` cru vira o phone_number, que é o JID do WhatsApp.
  def contact_id
    digits = @contact.phone_number.to_s.delete('^0-9')
    "#{digits}@c.us" if digits.present?
  end
end
