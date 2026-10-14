# Convite que nunca sai (#1454, decisão do Rodrigo na revisão): a regra do funil é convidar, mas ninguém pôde ser
# convidado (ninguém cuida do assunto, ou a notificação não saiu). Passado o prazo do convite (o mesmo TTL da etapa,
# padrão 24 h), contado desde a marca:
#   - a conversa continua segura com o robô (não volta ao rodízio nativo, para não furar a regra do funil);
#   - a marca passa a dizer "nao_conseguimos_chamar";
#   - uma vez só: atividade no card e notificação aos administradores da caixa (ou da conta, se a caixa não tem nenhum).
class Crm::Entrega::AvisoSemNinguem
  FALHA = 'nao_conseguimos_chamar'.freeze
  # Por que o convite não saiu. "intervalo" não entra: nesse caso um convite já saiu.
  FALHAS_DE_CONVITE = %w[convite_falhou ninguem_cuida nao_conseguimos_chamar].freeze
  EVENTO = 'entrega_sem_ninguem'.freeze

  def self.vencido?(conversation, plano)
    settings = plano.settings
    return false unless settings && settings[:handoff_mode] == 'r3_invite' && FALHAS_DE_CONVITE.include?(plano.motivo)

    desde = Crm::Entrega::Marca.desde(conversation)
    desde.present? && desde <= settings[:invite_ttl_seconds].to_i.seconds.ago
  end

  def initialize(conversation:, card:)
    @conversation = conversation
    @card = card
  end

  # Na memória da conversa (quem chama grava) e, fora dela, a atividade e as notificações.
  def avisar!
    return if Crm::Entrega::Marca.dados(@conversation)&.dig('avisado_em').present?

    Crm::Entrega::Marca.avisado!(@conversation)
    atividade!
    administradores.each { |admin| notificar(admin) }
  end

  private

  def atividade!
    return if @card.blank?

    Crm::ActivityLogger.new(card: @card, actor: nil, event_type: EVENTO, conversation: @conversation,
                            payload: { reason: FALHA }).perform
  end

  def administradores
    da_caixa = @conversation.inbox.members.where(id: admins_da_conta.select(:user_id))
    da_caixa.presence || User.where(id: admins_da_conta.select(:user_id))
  end

  def admins_da_conta
    AccountUser.where(account_id: @conversation.account_id).administrator
  end

  def notificar(admin)
    NotificationBuilder.new(notification_type: 'conversation_handoff_request', user: admin, account: @conversation.account,
                            primary_actor: @conversation, secondary_actor: nil).perform
  end
end
