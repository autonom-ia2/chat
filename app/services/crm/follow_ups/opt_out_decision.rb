# Grava no card o que o modelo decidiu sobre a resposta que parou a cadência (#1317): se foi pedido para parar,
# o card fica `opted_out` e o planner não o re-arma. Só age enquanto o estado ainda é o daquela parada — se um
# humano resetou a cadência, o planner a re-armou ou outra resposta chegou depois, a decisão velha não sobrescreve
# nada. A conferência se repete dentro do lock, porque a chamada ao modelo leva segundos.
#
# O log leva card, mensagem, decisão e motivo (códigos fechados). Nunca o texto da mensagem.
class Crm::FollowUps::OptOutDecision
  # Decisões que liberam o card para um ciclo novo. Qualquer outra (pendente, falhou, sem_credencial) segura o planner.
  CLEARED = %w[nao nao_se_aplica].freeze

  def initialize(card:, message:)
    @card = card
    @message = message
  end

  def perform
    return unless pending?

    result = Crm::Ai::OptOutClassifier.new(account: @card.account, message: @message).perform
    opted_out = result[:decision] == 'sim'
    return unless update_state(decision: result[:decision], motivo: result[:motivo], opted_out: opted_out)

    log_opt_out(result[:motivo]) if opted_out
    log(:info, "decisao=#{result[:decision]} motivo=#{result[:motivo]}")
  end

  # A decisão não saiu (provedor fora, sem chave de IA). Fica visível no estado do card e no log, e o planner não re-arma
  # o card até alguém resetar a cadência. Só a classe do erro vai ao log: a mensagem do provedor pode ecoar o input, e o
  # detalhe da chamada já sai no log do próprio ResponsesClient.
  def record_failure(status, error)
    log(:error, "decisao=#{status} erro=#{error.class.name}")
    update_state(decision: status, motivo: error.class.name, opted_out: false)
  end

  private

  def pending?
    state = auto_followup_state
    state['opt_out_decision'] == 'pendente' && state['stopped_message_id'] == @message.id
  end

  def update_state(decision:, motivo:, opted_out:)
    @card.with_lock do
      next false unless pending?

      metadata = (@card.metadata || {}).deep_dup
      metadata['ai'] ||= {}
      extra = opted_out ? { 'opted_out' => true, 'stopped_reason' => 'opt_out' } : {}
      metadata['ai']['auto_followup_state'] = auto_followup_state.merge(
        'opt_out_decision' => decision, 'opt_out_motivo' => motivo, **extra
      )
      @card.update!(metadata: metadata)
    end
  end

  def auto_followup_state
    (@card.metadata || {}).fetch('ai', {}).to_h.fetch('auto_followup_state', {}).to_h
  end

  def log_opt_out(motivo)
    Crm::ActivityLogger.new(
      card: @card,
      actor: nil,
      event_type: 'ai_followup_stopped',
      conversation: @card.primary_conversation,
      payload: { reason: 'opt_out', trigger: 'opt_out_decision', message_id: @message.id, motivo: motivo }
    ).perform
  end

  def log(level, details)
    Rails.logger.public_send(level, "[crm][ai][opt_out] card_id=#{@card.id} message_id=#{@message.id} #{details}")
  end
end
