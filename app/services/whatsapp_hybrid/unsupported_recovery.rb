# Recupera pelo aparelho conectado (WAHA) a mensagem que a Cloud entregou como "não suportada" (chat#1489).
#
# Ao nascer a bolha, numa caixa com WhatsApp API pronto e na conta com a flag `whatsapp_hybrid_recovery`, a mensagem
# ganha `whatsapp_web_id` (o id físico tirado do wamid) e `hybrid_recovery: pending`, e o RecoverUnsupportedJob passa
# a perguntar ao motor por ela (pull: nada de assinar o evento `message`). Cada tentativa é um `attempt!`:
#   :retry — o motor ainda não tem a mensagem (404), não respondeu, ou a conexão não está pronta agora;
#   :done  — recuperou, ou falhou de vez (mídia, nada legível, não casou, mais de uma candidata, flag desligada).
#
# Casamento com certeza, todas juntas: id igual, `fromMe: false`, remetente = contato da conversa, sessão da caixa da
# mensagem e uma candidata só. Faltando uma, a bolha fica com o aviso.
#
# A própria Message recebe o texto (posição e horário não mudam) e o `message_updated` normal leva à tela. Toda escrita
# é sob trava, sobre o registro relido, e só mexe nas chaves desta recuperação (#1560). Nada de conteúdo vai ao log.
class WhatsappHybrid::UnsupportedRecovery
  FEATURE = 'whatsapp_hybrid_recovery'.freeze
  STATE_KEY = 'hybrid_recovery'.freeze
  REASON_KEY = 'hybrid_recovery_reason'.freeze
  WEB_ID_KEY = 'whatsapp_web_id'.freeze
  VIA_KEY = 'recovered_via'.freeze
  UNSUPPORTED_KEY = 'is_unsupported'.freeze
  PENDING = 'pending'.freeze
  RECOVERED = 'recovered'.freeze
  FAILED = 'failed'.freeze

  # A nossa IA espera a recuperação até aqui; depois, não responde ao aviso.
  AI_WAIT = 2.minutes
  DEADLINE = 30.minutes
  RETRY_DELAYS = [5.seconds, 15.seconds, 30.seconds, 1.minute, 2.minutes, 5.minutes, 10.minutes].freeze

  C_US = '@c.us'.freeze
  S_WHATSAPP = '@s.whatsapp.net'.freeze

  # Chaves que a bolha já nasce com elas, ou {} quando a caixa não recupera.
  def self.initial_attributes(inbox, wamid)
    web_id = WhatsappHybrid::Wamid.message_id(wamid.to_s)
    return {} unless safe_web_id?(web_id) && connection_for(inbox)

    { WEB_ID_KEY => web_id, STATE_KEY => PENDING }
  end

  # O id vai no caminho da URL do motor: só letras e dígitos (os ids do WhatsApp são hexadecimais).
  def self.safe_web_id?(web_id)
    web_id.present? && web_id.delete('A-Za-z0-9').empty?
  end

  # Conexão da própria caixa, pronta (conectada, mesmo número, envio automático ligado), na conta liberada.
  def self.connection_for(inbox)
    return unless inbox.account.feature_enabled?(FEATURE) && WhatsappHybrid::Config.available_for?(inbox)

    connection = WhatsappHybrid::Connection.find_by(inbox_id: inbox.id)
    connection if connection&.routable? && connection.inbox_id == inbox.id
  end

  def self.pending?(message)
    message.content_attributes.to_h.with_indifferent_access[STATE_KEY] == PENDING
  end

  def initialize(message)
    @message = message
  end

  def attempt!
    return :done unless self.class.pending?(@message)
    return fail!('disabled') unless @message.account.feature_enabled?(FEATURE)
    return fail!('invalid_id') unless self.class.safe_web_id?(web_id)

    connection = self.class.connection_for(@message.inbox)
    return :retry if connection.nil?
    return fail!('chat_unknown') if chat_ids.empty?

    candidates = fetch(connection)
    return :retry if candidates.nil?

    settle(candidates)
  end

  def fail!(reason)
    write { |attrs| [nil, attrs.merge(STATE_KEY => FAILED, REASON_KEY => reason)] }
    log("failed reason=#{reason}")
    :done
  end

  private

  # nil quando nenhuma consulta respondeu com a mensagem (tenta de novo); senão, as que responderam.
  def fetch(connection)
    client = Waha::Client.new
    found = chat_ids.filter_map { |chat_id| lookup(client, connection, chat_id) }
    found.presence
  end

  def lookup(client, connection, chat_id)
    payload = client.get_message(connection.session_name, chat_id, web_id)
    payload.is_a?(Array) ? payload : [payload]
  rescue Waha::Client::Error => e
    log("lookup error=#{e.class} status=#{e.status}")
    nil
  end

  def settle(candidates)
    matches = candidates.flatten.select { |payload| match?(payload) }
    return fail!(matches.empty? ? 'mismatch' : 'ambiguous') unless matches.size == 1

    apply(WhatsappHybrid::RecoveredContent.from_payload(matches.first))
  end

  def match?(payload)
    payload.is_a?(Hash) && payload['id'].to_s.split('_').last == web_id && payload['fromMe'] == false &&
      sender_ids.include?(normalized(payload['from']))
  end

  def apply(content)
    case content.kind
    when :text then recovered!(content.text)
    when :media then media!(content.text)
    else fail!('unreadable')
    end
  end

  def recovered!(text)
    changed = write do |attrs|
      [text, attrs.except(UNSUPPORTED_KEY, REASON_KEY).merge(STATE_KEY => RECOVERED, VIA_KEY => 'web')]
    end
    return :done unless changed

    log('recovered')
    wake_ai
    :done
  end

  # Mídia fica para a PR 3: guarda só a legenda; sem legenda, a bolha continua com o aviso.
  def media!(caption)
    write do |attrs|
      failed = attrs.merge(STATE_KEY => FAILED, REASON_KEY => 'media')
      caption.present? ? [caption, failed.except(UNSUPPORTED_KEY).merge(VIA_KEY => 'web')] : [nil, failed]
    end
    log('failed reason=media')
    :done
  end

  # Sob trava, sobre o registro relido; só quando ainda está pendente. O bloco devolve [conteúdo novo ou nil, atributos].
  def write
    @message.with_lock do
      attrs = @message.content_attributes.to_h
      next false unless attrs[STATE_KEY] == PENDING && attrs[WEB_ID_KEY] == web_id

      content, new_attrs = yield(attrs)
      changes = { content_attributes: new_attrs }
      changes[:content] = content if content
      @message.update!(changes)
      true
    end
  end

  # A nossa IA não respondeu ao aviso (MessageListener). Recuperada dentro da espera, é chamada uma vez.
  def wake_ai
    return if Time.current > @message.created_at + AI_WAIT

    ::Autonomia::Agents::Operate::ReplyJob.perform_later(@message.conversation_id, @message.id)
  end

  def web_id
    @web_id ||= @message.content_attributes.to_h[WEB_ID_KEY].to_s
  end

  def contact
    @message.conversation.contact
  end

  # O número do contato em `@c.us` (o caminho do spike), mais o chat id que o motor já guardou nele, se for `@c.us`.
  # Contato só com `@lid`: o cliente não tem o mapeamento de LID, então não há chat para perguntar.
  def chat_ids
    @chat_ids ||= begin
      phone = contact&.phone_number.to_s.delete('^0-9')
      known = Waha::ContactChatId.values(contact, :chat_id, :jid).select { |id| phone_chat_id?(id) }
      ([phone.present? ? "#{phone}#{C_US}" : nil] + known).compact.uniq
    end
  end

  # `<dígitos>@c.us`: também vai no caminho da URL do motor.
  def phone_chat_id?(chat_id)
    digits = chat_id.delete_suffix(C_US)
    chat_id.end_with?(C_US) && digits.present? && digits.delete('0-9').empty?
  end

  def sender_ids
    @sender_ids ||= chat_ids + [contact&.custom_attributes.to_h[Waha::ContactChatId::LID]].compact
  end

  def normalized(jid)
    value = jid.to_s
    value.end_with?(S_WHATSAPP) ? "#{value.delete_suffix(S_WHATSAPP)}#{C_US}" : value
  end

  def log(outcome)
    Rails.logger.info("[whatsapp_hybrid] recovery #{outcome} message=#{@message.id} inbox=#{@message.inbox_id}")
  end
end
