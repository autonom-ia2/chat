# Foto de perfil do contato na caixa híbrida (#1934). A Cloud não manda a foto e não tem endpoint para buscar; a sessão
# WAHA da própria caixa (o mesmo número) vê a foto como o WhatsApp do celular vê. Decisão do Rodrigo (20/10): buscar
# só no híbrido; a Cloud pura fica sem foto.
# - Gatilho (`after_commit` de Message): mensagem recebida numa caixa híbrida, de contato sem foto, com a flag ligada.
#   No máximo 1 tentativa a cada 7 dias por contato (marca no Redis, gravada antes de consultar o motor).
# - A busca (WhatsappHybrid::FotoDoContatoJob): só com a sessão conectada, não pausada e no mesmo número da caixa.
#   Achou: Avatar::AvatarFromUrlJob baixa o arquivo (a URL do WhatsApp expira). Sem foto ou escondida pela
#   privacidade: só tenta de novo em 30 dias, sem aviso nem erro.
# - Ritmo por sessão: no máximo 1 consulta a cada 15 s e 300 por dia. Sem vaga, desiste sem marcar o contato: a
#   próxima mensagem dele tenta de novo. Uma rajada (campanha recebendo respostas) não vira rajada no motor.
# - Qualquer erro do motor (limite de consultas, conexão, 404 de sessão, resposta estranha) para as buscas daquela
#   sessão por 1 hora e desfaz a marca do contato.
class WhatsappHybrid::FotoDoContato
  FLAG = 'hibrido_foto_do_contato'.freeze
  INTERVALO = 7.days
  SEM_FOTO = 30.days
  PAUSA_DA_SESSAO = 1.hour
  RITMO = 15.seconds
  TETO_DIARIO = 300
  TIMEOUT = 10

  def self.after_commit(message)
    return unless buscar_para?(message)

    WhatsappHybrid::FotoDoContatoJob.perform_later(message.sender_id, message.inbox_id)
  rescue StandardError => e
    Rails.logger.error("[whatsapp_hybrid] foto do contato (gatilho) #{e.class}")
  end

  # Do mais barato ao mais caro: a foto já anexada é a única consulta ao banco.
  def self.buscar_para?(message)
    message.incoming? && message.sender_type == 'Contact' && message.account.feature_enabled?(FLAG) &&
      WhatsappHybrid::Config.hybrid_inbox?(message.inbox_id) &&
      !::Redis::Alfred.exists?(chave_do_contato(message.sender_id)) && !message.sender.avatar.attached?
  end

  def self.chave_do_contato(contact_id)
    "whatsapp_hybrid:foto_do_contato:#{contact_id}"
  end

  def self.chave_da_sessao(session_name)
    "whatsapp_hybrid:foto_do_contato:pausa:#{session_name}"
  end

  def initialize(contact:, connection:, client: Waha::Client.new)
    @contact = contact
    @connection = connection
    @client = client
  end

  def perform
    return unless sessao_pronta? && contact_id
    # SET NX: dois jobs do mesmo contato (mensagens seguidas) não consultam o motor duas vezes.
    return unless ::Redis::Alfred.set(self.class.chave_do_contato(@contact.id), 1, nx: true, ex: INTERVALO.to_i)
    return devolver_o_contato unless vaga_na_sessao?

    url = url_da_foto
    return Avatar::AvatarFromUrlJob.perform_later(@contact, url) if url

    ::Redis::Alfred.setex(self.class.chave_do_contato(@contact.id), 1, SEM_FOTO.to_i)
  rescue StandardError => e
    pausar_a_sessao(e)
  end

  private

  def sessao_pronta?
    @connection.status == 'connected' && !@connection.paused? && @connection.same_number? &&
      !::Redis::Alfred.exists?(self.class.chave_da_sessao(@connection.session_name))
  end

  # 1 consulta a cada RITMO por sessão (SET NX) e no máximo TETO_DIARIO por dia.
  def vaga_na_sessao?
    sessao = @connection.session_name
    return false unless ::Redis::Alfred.set("whatsapp_hybrid:foto_do_contato:ritmo:#{sessao}", 1, nx: true, ex: RITMO.to_i)

    chave_do_dia = "whatsapp_hybrid:foto_do_contato:dia:#{sessao}:#{Time.current.utc.to_date}"
    usadas = ::Redis::Alfred.incr(chave_do_dia)
    ::Redis::Alfred.expire(chave_do_dia, 1.day.to_i) if usadas == 1
    usadas <= TETO_DIARIO
  end

  def devolver_o_contato
    ::Redis::Alfred.delete(self.class.chave_do_contato(@contact.id))
  end

  # Resposta que não é o formato esperado é erro do motor, não "sem foto".
  def url_da_foto
    resposta = @client.profile_picture(session: @connection.session_name, contact_id: contact_id, timeout: TIMEOUT)
    raise Waha::Client::InvalidResponse, 'foto do contato: resposta sem objeto' unless resposta.is_a?(Hash)

    resposta['profilePictureURL'].presence
  end

  def pausar_a_sessao(error)
    devolver_o_contato
    ::Redis::Alfred.setex(self.class.chave_da_sessao(@connection.session_name), 1, PAUSA_DA_SESSAO.to_i)
    status = error.respond_to?(:status) ? error.status.inspect : '-'
    Rails.logger.warn("[whatsapp_hybrid] foto do contato: busca pausada na sessão inbox=#{@connection.inbox_id} " \
                      "status=#{status} #{error.class}")
  end

  def contact_id
    digits = @contact.phone_number.to_s.delete('^0-9')
    "#{digits}@c.us" if digits.present?
  end
end
