# Freio do WhatsApp API quando o WhatsApp limita conversas novas pelos aparelhos conectados (chat#1486).
# Sem sinal do WhatsApp nada muda e nenhuma prova é consultada. Com o limite ativo (Timelock), o WhatsApp só
# entrega para quem já conversa com o aparelho, e insistir com contato novo agrava o limite.
# Prova de "o aparelho já conversou", contada a partir do pareamento atual (o token de privacidade parece ser do
# aparelho: no incidente de 13/10, 19 mensagens recebidas antes do pareamento do dia não bastaram):
# uma mensagem recebida do contato nesta caixa, ou uma saída para ele pelo WhatsApp API com envio confirmado.
# O erro 463 do motor (conversa sem token de privacidade) deixa o contato 6 h fora do WhatsApp API, sem reenvio.
class WhatsappHybrid::ReachOut
  ENGINE_ERROR = 'error 463'.freeze
  BLOCK_FOR = 6.hours
  PAIRED_AT_TTL = 120.days.to_i
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

  # Hora do pareamento atual do aparelho. Em Redis para não criar coluna; quem grava é o SessionManager.
  def self.paired!(connection, at: Time.current)
    ::Redis::Alfred.setex(paired_at_key(connection), at.to_i, PAIRED_AT_TTL)
  end

  def self.paired_at(connection)
    raw = ::Redis::Alfred.get(paired_at_key(connection)).presence
    raw && Time.zone.at(raw.to_i)
  end

  def self.paired_at_key(connection)
    "whatsapp_hybrid:paired_at:#{connection.id}"
  end

  def initialize(connection, contact)
    @connection = connection
    @contact = contact
  end

  # Sem limite ativo, sai antes de qualquer consulta de prova.
  def allowed?
    return false if blocked?
    return true unless timelock.active?

    known_contact?
  end

  def blocked?
    blocked_until.present?
  end

  # Guarda até quando vale o bloqueio, para a falha dizer a hora.
  def block!
    ::Redis::Alfred.setex(key, BLOCK_FOR.from_now.to_i, BLOCK_FOR.to_i)
  end

  # A hora dita é a mais tarde entre o fim do limite (quando barra o contato) e o fim do bloqueio do 463.
  def refusal_text
    ends = [blocked_until]
    if timelock_restricts?
      return LIMITED_ERROR if timelock.current['ends_at'].blank?

      ends << timelock.current['ends_at']
    end
    ends_at = ends.compact_blank.map(&:to_i).max
    return LIMITED_ERROR if ends_at.nil?

    format(LIMITED_UNTIL_ERROR, hora: TemplateFields::Format.time(Time.zone.at(ends_at), zone))
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

  def blocked_until
    ::Redis::Alfred.get(key).presence
  end

  # Sem hora de pareamento (Redis perdido, conexão pareada antes do chat#1486): vale só o envio pelo WhatsApp API
  # aceito, sem limite de tempo, como era antes. Mensagem recebida sem a hora não prova nada sobre este aparelho.
  def known_contact?
    return @known_contact if defined?(@known_contact)

    paired_at = self.class.paired_at(@connection)
    @known_contact = (paired_at.present? && received_since?(paired_at)) || web_sent_since?(paired_at)
  end

  def received_since?(paired_at)
    contact_messages(Message.incoming).exists?(['messages.created_at >= ?', paired_at])
  end

  # `content_attributes` é JSON dupla-codificado: o LIKE é a peneira barata e quem decide é a leitura em Ruby.
  def web_sent_since?(paired_at)
    scope = contact_messages(Message.outgoing).where(status: CONFIRMED_STATUSES)
                                              .where('messages.content_attributes::text LIKE ?', '%whatsapp_transport%')
    scope = scope.where(messages: { created_at: paired_at.. }) if paired_at
    scope.unscope(:order).select(:id, :content_attributes).find_each(batch_size: 50).any? do |message|
      message.content_attributes.to_h['whatsapp_transport'] == WEB_TRANSPORT
    end
  end

  def contact_messages(scope)
    scope.joins(:conversation).where(inbox_id: @connection.inbox_id, conversations: { contact_id: @contact.id })
  end

  def phone
    @contact.phone_number.to_s.delete('^0-9')
  end

  # Fuso da conta; sem fuso na conta, o padrão do CRM (Brasília).
  def zone
    TemplateFields::Format.account_zone(@connection.account)
  end
end
