# Pedido de parar na resposta a uma campanha do WhatsApp (#1449): a primeira resposta do cliente depois de uma mensagem de
# campanha (modelo ou texto livre das 24 h, marcada com `campaign_id` ou `whatsapp_api_campaign_id`) vai ao modelo, e no
# "sim" o contato ganha a recusa de mensagens ativas com a origem 'campaign_reply'. Daí em diante ele sai das próximas
# campanhas, que já filtram `not_opted_out`.
#
# - Quem decide é o modelo (Crm::Ai::OptOutClassifier, o mesmo do follow-up de IA), com a saída "nao_se_aplica" e, na
#   dúvida, "nao". Nada de lista de palavras.
# - Só a primeira resposta com texto, e só se a última mensagem pública enviada antes dela for a da campanha, de até
#   WINDOW atrás. "Oi" seguido de "SAIR" avalia só o "oi"; resposta depois de alguém da equipe escrever não é à campanha.
#   A ordem é por created_at: a mensagem da campanha gravada na resposta (SentMessageRecorder#record_at_reply) leva a
#   data do envio, mas id maior. Por isso o job sai do ReplyMarkJob, depois dessa gravação, e o modelo recebe essa
#   mensagem como contexto. Essa gravação só acontece dentro da janela do ReplyMarker (72 h): na campanha do WhatsApp
#   Oficial por público sem conversa aberta no envio, a janela efetiva é essa.
# - Resposta de botão (`content_attributes.selected_option`) não passa por aqui: o botão tem o caminho dele, sem IA.
# - Mensagem sem texto, contato que já recusou (por qualquer origem) e caixa que não é WhatsApp (oficial ou API) não
#   chegam ao modelo.
# - Teto de DAILY_LIMIT mensagens avaliadas por conta por dia (UTC), uma vaga por mensagem. A decisão fica guardada por
#   mensagem: rodar de novo depois de uma decisão não paga outra chamada.
# - Custo na Gestão IA pela feature FEATURE. O log leva ids e códigos, nunca o texto do cliente.
# - A recusa vale pelo número (Contacts::CampaignReplyOptOut). Quem a desfaz é a equipe, no painel do contato
#   (Contacts::OptOutsController).
class CampaignJourney::OptOutReply
  FEATURE = 'campanha_opt_out'.freeze
  WINDOW = 7.days
  DAILY_LIMIT = 500
  COUNTER_TTL = 2.days
  # Cobre as tentativas do job e o retry padrão do Sidekiq com folga.
  CLASSIFICATION_TTL = 1.day
  CAMPAIGN_KEYS = %w[campaign_id whatsapp_api_campaign_id].freeze
  BUTTON_KEY = 'selected_option'.freeze

  def self.counter_key(account_id, day = Time.current.utc.to_date)
    "campaign_journey:opt_out_reply:#{account_id}:#{day.strftime('%Y%m%d')}"
  end

  def initialize(message)
    @message = message
    @conversation = message.conversation
    @contact = @conversation&.contact
  end

  def applicable?
    candidate? && campaign_message.present? && first_reply?
  end

  def perform
    return unless applicable?

    result = classify
    return log(:warn, 'limite_diario') if result.nil?

    Contacts::CampaignReplyOptOut.mark!(@contact) if result[:decision] == 'sim'
    log(:info, "decisao=#{result[:decision]} motivo=#{result[:motivo]}")
  end

  private

  def candidate?
    @message.incoming? && !@message.private? && @contact.present? && !@contact.opted_out? &&
      @message.content.present? && !button_reply? && whatsapp_inbox?
  end

  def button_reply?
    @message.content_attributes.to_h.key?(BUTTON_KEY)
  end

  def whatsapp_inbox?
    inbox = @message.inbox
    inbox.whatsapp? || inbox.api?
  end

  # A última mensagem pública enviada antes da resposta, se for da campanha e estiver dentro da janela.
  def campaign_message
    return @campaign_message if defined?(@campaign_message)

    last = @conversation.messages.outgoing.where(private: false)
                        .where(created_at: (@message.created_at - WINDOW)...@message.created_at)
                        .reorder(created_at: :desc, id: :desc).first
    @campaign_message = last if last && campaign_marked?(last)
  end

  def campaign_marked?(message)
    attributes = message.additional_attributes.to_h
    CAMPAIGN_KEYS.any? { |key| attributes[key].present? }
  end

  # Primeira resposta com texto: foto, áudio ou figurinha antes do texto não contam (não foram ao modelo).
  def first_reply?
    @conversation.messages.incoming.where(created_at: campaign_message.created_at..@message.created_at)
                 .where.not(id: @message.id).where.not(content: [nil, '']).none?
  end

  # nil quando o teto do dia já foi atingido. A decisão guardada só tem os códigos do schema, nunca o texto.
  def classify
    cached = Redis::Alfred.get(message_key('decision'))
    return JSON.parse(cached, symbolize_names: true) if cached
    return unless reserve!

    classifier = Crm::Ai::OptOutClassifier.new(account: @message.account, message: @message, feature: FEATURE,
                                               previous_message: campaign_message.content.to_s)
    result = classifier.perform
    Redis::Alfred.setex(message_key('decision'), result.to_json, CLASSIFICATION_TTL.to_i)
    result
  end

  # Uma vaga do teto por mensagem, reservada de forma atômica (SET NX): a nova tentativa do job (provedor fora, resposta
  # fora do schema) usa a mesma vaga. Sem vaga no dia, a reserva sai, para não liberar a chamada numa tentativa seguinte.
  def reserve!
    return true unless Redis::Alfred.set(message_key('reserved'), '1', nx: true, ex: CLASSIFICATION_TTL.to_i)

    key = self.class.counter_key(@message.account_id)
    count = Redis::Alfred.incr(key)
    Redis::Alfred.expire(key, COUNTER_TTL.to_i) if count == 1
    return true if count <= DAILY_LIMIT

    Redis::Alfred.delete(message_key('reserved'))
    false
  end

  def message_key(kind)
    "campaign_journey:opt_out_reply:#{kind}:#{@message.id}"
  end

  def log(level, details)
    Rails.logger.public_send(
      level,
      "[campaign_journey][opt_out_reply] account=#{@message.account_id} conversation=#{@conversation.id} message=#{@message.id} #{details}"
    )
  end
end
