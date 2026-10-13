# Freio do WhatsApp API quando o WhatsApp limita conversas novas pelos aparelhos conectados (chat#1486).
# Sem sinal do WhatsApp nada muda. Com o limite ativo (Timelock), o WhatsApp só entrega para quem já conversa
# com o aparelho, e insistir com contato novo agrava o limite. Prova de "já conversou": uma saída anterior desta
# caixa para este contato pelo WhatsApp API, com envio confirmado. O erro 463 do motor (conversa sem token de
# privacidade) deixa o contato 6 h fora do WhatsApp API, sem reenvio.
class WhatsappHybrid::ReachOut
  ENGINE_ERROR = 'error 463'.freeze
  BLOCK_FOR = 6.hours
  CONFIRMED_STATUSES = %w[sent delivered read].freeze
  WEB_TRANSPORT = 'web'.freeze
  BLOCKED_ERROR = 'O WhatsApp limitou conversas novas por este número agora. Para este contato, use uma mensagem ' \
                  'pronta (modelo aprovado).'.freeze
  LIMITED_UNTIL_ERROR = 'O WhatsApp limitou conversas novas por este número até %<hora>s. Use uma mensagem pronta.'.freeze
  LIMITED_ERROR = 'O WhatsApp limitou conversas novas por este número por enquanto. Use uma mensagem pronta.'.freeze

  # Texto técnico do motor (whatsmeow), não fala de usuário.
  def self.engine_refusal?(error)
    error.message.to_s.include?(ENGINE_ERROR)
  end

  def initialize(connection, contact)
    @connection = connection
    @contact = contact
  end

  def allowed?
    !blocked? && !timelock_restricts?
  end

  def blocked?
    blocked_until.present?
  end

  # Guarda até quando vale o bloqueio, para a falha dizer a hora.
  def block!
    ::Redis::Alfred.setex(key, BLOCK_FOR.from_now.to_i, BLOCK_FOR.to_i)
  end

  def refusal_text
    ends_at = limited_until
    return LIMITED_ERROR if ends_at.blank?

    format(LIMITED_UNTIL_ERROR, hora: TemplateFields::Format.time(Time.zone.at(ends_at.to_i), zone))
  end

  def key
    "whatsapp_hybrid:reachout_block:#{@connection.id}:#{phone}"
  end

  private

  def timelock
    @timelock ||= WhatsappHybrid::Timelock.new(@connection)
  end

  def timelock_restricts?
    timelock.active? && !known_contact?
  end

  def limited_until
    timelock_restricts? ? timelock.current['ends_at'] : blocked_until
  end

  def blocked_until
    ::Redis::Alfred.get(key).presence
  end

  # `content_attributes` é JSON dupla-codificado: o LIKE é a peneira barata e quem decide é a leitura em Ruby.
  def known_contact?
    return @known_contact if defined?(@known_contact)

    @known_contact = web_messages.select(:id, :content_attributes).find_each.any? do |message|
      message.content_attributes.to_h['whatsapp_transport'] == WEB_TRANSPORT
    end
  end

  def web_messages
    Message.outgoing.joins(:conversation)
           .where(inbox_id: @connection.inbox_id, status: CONFIRMED_STATUSES, conversations: { contact_id: @contact.id })
           .where('messages.content_attributes::text LIKE ?', '%whatsapp_transport%')
  end

  def phone
    @contact.phone_number.to_s.delete('^0-9')
  end

  # Fuso da conta; sem fuso na conta, o padrão do CRM (Brasília).
  def zone
    TemplateFields::Format.account_zone(@connection.account)
  end
end
