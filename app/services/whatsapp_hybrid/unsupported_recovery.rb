# Recupera pelo aparelho conectado (WAHA) a mensagem que a Cloud entregou como "não suportada" (chat#1489).
#
# Ao nascer a bolha, numa caixa com WhatsApp API pronto, na conta com a flag `whatsapp_hybrid_recovery` e quando o
# `unsupported.type` é de mensagem nova (RECOVERABLE_TYPES), a mensagem ganha `whatsapp_web_id` (o id físico tirado do
# wamid) e `hybrid_recovery: pending`, e o RecoverUnsupportedJob passa a perguntar ao motor por ela (pull). Cada
# tentativa é um `attempt!`:
#   :retry — o motor ainda não tem a mensagem (404), não respondeu, respondeu sem mensagem, a mensagem ainda veio
#            sem conteúdo (`_data.Message` vazio), ou a conexão não está pronta agora. O job desiste em 30 minutos;
#   :done  — recuperou, ou falhou de vez (mídia, tipo que não lemos, não casou, mais de uma candidata, flag desligada).
#
# Casamento com certeza, todas juntas: id igual, `fromMe: false`, remetente = contato da conversa, sessão da caixa da
# mensagem e uma candidata só. Faltando uma, a bolha fica com o aviso.
#
# A própria Message recebe o texto (posição e horário não mudam) e o `message_updated` normal leva à tela. Toda escrita
# é sob trava, sobre o registro relido, e só mexe nas chaves desta recuperação (#1560). Nada de conteúdo vai ao log.
# Quem decide se a IA é chamada é o WhatsappHybrid::RecoveryAiWake.
class WhatsappHybrid::UnsupportedRecovery
  FEATURE = 'whatsapp_hybrid_recovery'.freeze
  STATE_KEY = 'hybrid_recovery'.freeze
  REASON_KEY = 'hybrid_recovery_reason'.freeze
  HEADER_KEY = 'hybrid_recovery_header'.freeze
  RECOVERED_AT_KEY = 'hybrid_recovered_at'.freeze
  # Avisa quem precisa saber (Multifunil) que a mensagem foi recuperada. Só ids, uma vez, depois do commit.
  RECOVERED_EVENT = 'whatsapp_hybrid.message_recovered'.freeze
  WEB_ID_KEY = 'whatsapp_web_id'.freeze
  VIA_KEY = 'recovered_via'.freeze
  UNSUPPORTED_KEY = 'is_unsupported'.freeze
  PENDING = 'pending'.freeze
  RECOVERED = 'recovered'.freeze
  FAILED = 'failed'.freeze

  # `unsupported.type` de mensagem nova (nil é o erro 131060, sem tipo). Edição, reação, voto, fixar e afins mexem
  # numa mensagem que já existe: não viram bolha nova, então ficam com o aviso e sem job.
  RECOVERABLE_TYPES = [nil, 'hsm', 'interactive', 'button', 'list', 'template'].freeze

  DEADLINE = 30.minutes
  RETRY_DELAYS = [5.seconds, 15.seconds, 30.seconds, 1.minute, 2.minutes, 5.minutes, 10.minutes].freeze

  C_US = '@c.us'.freeze
  S_WHATSAPP = '@s.whatsapp.net'.freeze

  # Chaves que a bolha já nasce com elas, ou {} quando não há o que recuperar.
  def self.initial_attributes(inbox, wamid, unsupported_type)
    return {} unless RECOVERABLE_TYPES.include?(unsupported_type)

    web_id = WhatsappHybrid::Wamid.message_id(wamid.to_s)
    return {} unless safe_web_id?(web_id) && connection_for(inbox)

    { WEB_ID_KEY => web_id, STATE_KEY => PENDING }
  end

  # O id vai no caminho da URL do motor: só letras e dígitos (os ids do WhatsApp são hexadecimais).
  def self.safe_web_id?(web_id)
    web_id.present? && web_id.delete('A-Za-z0-9').empty?
  end

  # Conexão da própria caixa (buscada pelo inbox_id), pronta: conectada, mesmo número, envio automático ligado.
  def self.connection_for(inbox)
    return unless inbox.account.feature_enabled?(FEATURE) && WhatsappHybrid::Config.available_for?(inbox)

    connection = WhatsappHybrid::Connection.find_by(inbox_id: inbox.id)
    connection if connection&.routable?
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
    return :retry if candidates.empty?

    settle(candidates)
  end

  # A bolha fica com o aviso. A IA não responde: o motivo vai ao evento do agente e, com a flag ligada, a conversa passa
  # para as pessoas com uma nota (Operate::NaoSuportada). Só quando a falha é nova.
  def fail!(reason)
    changed = write { |attrs| [nil, attrs.merge(STATE_KEY => FAILED, REASON_KEY => reason)] }
    return :done unless changed

    log("failed reason=#{reason}")
    ::Autonomia::Agents::Operate::NaoSuportada.falhou(@message)
    :done
  end

  private

  # As mensagens que o motor devolveu (só objetos), de todos os chats perguntados.
  def fetch(connection)
    client = Waha::Client.new
    chat_ids.flat_map { |chat_id| lookup(client, connection, chat_id) }.select { |payload| payload.is_a?(Hash) }
  end

  def lookup(client, connection, chat_id)
    Array.wrap(client.get_message(connection.session_name, chat_id, web_id))
  rescue Waha::Client::Error => e
    log("lookup error=#{e.class} status=#{e.status}")
    []
  end

  # Todas as que casam têm o mesmo id físico (`match?`). A mesma mensagem pode voltar por mais de um chat perguntado,
  # com o id composto diferente: conta uma vez por remetente. Dois remetentes diferentes com o mesmo id: ambígua.
  def settle(candidates)
    matches = candidates.select { |payload| match?(payload) }.uniq { |payload| normalized(payload['from']) }
    return fail!(matches.empty? ? 'mismatch' : 'ambiguous') unless matches.size == 1

    apply(WhatsappHybrid::RecoveredContent.from_payload(matches.first))
  end

  def match?(payload)
    payload['id'].to_s.split('_').last == web_id && payload['fromMe'] == false &&
      sender_ids.include?(normalized(payload['from']))
  end

  # Conteúdo que ainda não chegou ao motor: tenta de novo até o prazo. Tipo que não lemos: falha já (fica o aviso).
  def apply(content)
    case content.kind
    when :text then recovered!(content)
    when :media then media!(content)
    when :unreadable then fail!('unreadable')
    else :retry
    end
  end

  # `hybrid_recovered_at` vai no mesmo update que troca o estado (nunca o updated_at).
  # TODO(#1637): EsperaDoAssunto conta o teto a partir de max(created_at, hybrid_recovered_at). Issue dos Agentes IA #1637.
  def recovered!(content)
    finish!('recovered', announce: true) do |attrs|
      recovered = { STATE_KEY => RECOVERED, VIA_KEY => 'web', RECOVERED_AT_KEY => Time.current.utc.iso8601 }
      [content.text, attrs.except(UNSUPPORTED_KEY, REASON_KEY).merge(recovered).merge(header_mark(content))]
    end
    :done
  end

  def header_mark(content)
    content.header_media ? { HEADER_KEY => content.header_media.to_s } : {}
  end

  # Mídia fica para a PR 3: guarda só a legenda (e aí a IA pode ser chamada); sem legenda, a bolha fica com o aviso.
  # A marca do arquivo (`hybrid_recovery_header`) vai junto, para a IA saber que havia um arquivo que não leu.
  def media!(content)
    return fail!('media') if content.text.blank?

    finish!('failed reason=media') do |attrs|
      failed = { STATE_KEY => FAILED, REASON_KEY => 'media', VIA_KEY => 'web' }
      [content.text, attrs.except(UNSUPPORTED_KEY).merge(failed).merge(header_mark(content))]
    end
  end

  def finish!(outcome, announce: false, &)
    return :done unless write(&)

    log(outcome)
    announce_recovered if announce
    WhatsappHybrid::RecoveryAiWake.call(@message)
    :done
  end

  # Depois do commit (fora da transação, mesmo se alguém chamar dentro de uma). Só na transição pending -> recovered.
  def announce_recovered
    payload = { message_id: @message.id, conversation_id: @message.conversation_id, account_id: @message.account_id }
    ActiveRecord.after_all_transactions_commit { ActiveSupport::Notifications.instrument(RECOVERED_EVENT, payload) }
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
