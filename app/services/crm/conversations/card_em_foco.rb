# Toda mensagem do cliente avalia o card em foco (#1675, épico #1140), atrás da flag de conta `crm_avaliar_toda_mensagem`.
#
# Na caixa sem card ao chegar (2+ funis, ou 1 funil em modo manual), a mensagem não fazia nada no card: só a troca de foco
# (Crm::Cards::Focus) e o card novo da IA de assunto agendavam a IA do CRM. O cliente que seguia no mesmo assunto
# ("fechado, quero contratar") não movia o card. Com a flag e a IA do CRM ligada, a mensagem do cliente:
#   1. agenda a avaliação do card em foco (Crm::Ai::Observer, com o debounce de sempre: uma rajada, uma avaliação); e
#   2. conta como atividade dele (last_message_at e last_activity_at com a hora da mensagem, só para a frente).
#
# Quem chama: o CardSyncer, com a IA de assunto desligada na caixa; o Crm::Subjects::IdentifyJob, depois da decisão do
# assunto, com ela ligada (o card em foco já é o do assunto decidido). Não agenda de novo quando a troca de foco, o card
# novo ou o card ao chegar já agendaram depois que a mensagem chegou, ou depois que o WhatsApp Híbrido trouxe o texto
# real dela (#1638).
#
# A atividade avança junto com a avaliação de propósito: o StaleCardsJob só reavalia card cuja última avaliação é anterior
# à última atividade, então a mensagem avaliada não volta a ser avaliada por estar parada.
class Crm::Conversations::CardEmFoco
  FLAG = 'crm_avaliar_toda_mensagem'.freeze

  def self.ligada?(account)
    account.present? && account.feature_enabled?(FLAG)
  end

  def initialize(conversation:, message:)
    @conversation = conversation
    @message = message
    @account = conversation.account
  end

  def perform
    return unless mensagem_do_cliente?

    card = Crm::Assunto.funil_atual(@conversation)
    return if card.nil?

    observer = Crm::Ai::Observer.new(card: card)
    observer.schedule_evaluation unless observer.agendada_desde?(chegada)
    Crm::Cards::Broadcaster.broadcast(card.reload, Events::Types::CRM_CARD_UPDATED) if registrar_atividade(card)
    card
  end

  private

  def mensagem_do_cliente?
    self.class.ligada?(@account) && Crm::Ai::Config.enabled? && @message&.incoming? && crm_da_caixa?
  end

  # O mesmo critério do CardSyncer: caixa sem configuração do CRM conta como ligada.
  def crm_da_caixa?
    setting = @account.crm_inbox_settings.find_by(inbox_id: @conversation.inbox_id)
    setting.nil? || setting.crm_enabled?
  end

  # Quando o texto da mensagem ficou disponível: a chegada, ou a recuperação pelo Híbrido (#1638), se veio depois.
  def chegada
    recuperada = @message.content_attributes.to_h['hybrid_recovered_at']
    return @message.created_at if recuperada.blank?

    [@message.created_at, Time.iso8601(recuperada.to_s)].max
  rescue ArgumentError
    @message.created_at
  end

  # Uma escrita condicional, só para a frente: mover de etapa grava a atividade com a hora de agora, e a hora desta
  # mensagem não pode voltá-la, nem a de outro job que rodou junto.
  def registrar_atividade(card)
    momento = @message.created_at
    cards = Crm::Card.where(id: card.id)
    atividade = cards.where(last_activity_at: nil).or(cards.where(last_activity_at: ...momento))
                     .update_all(last_activity_at: momento, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    mensagem = cards.where(last_message_at: nil).or(cards.where(last_message_at: ...momento))
                    .update_all(last_message_at: momento) # rubocop:disable Rails/SkipsModelValidations
    (atividade + mensagem).positive?
  end
end
