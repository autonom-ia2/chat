# Pergunta ao modelo se a resposta que parou a cadência de follow-up foi pedido para parar (#1317). A cadência já parou
# no `AutoFollowupCanceler`; aqui só se decide o rótulo `opted_out`.
#
# Provedor fora do ar ou resposta fora do schema: tenta de novo (cinco vezes, por uns minutos). Esgotado, ou sem chave de
# IA na conta, a falha fica gravada no estado do card (`opt_out_decision`) e no log — nada é engolido. Enquanto a decisão
# não sai, o planner não re-arma o card (fail closed, `AutoFollowupPlanner#opt_out_undecided?`).
#
# Erro transitório de banco ao gravar a decisão (o card e, no "sim", a recusa do contato vão juntos numa transação, #1325):
# nada fica gravado pela metade, e o job tenta de novo pelo mesmo caminho, com o mesmo teto. Esgotado, grava "falhou".
# Erro que não passa sozinho (registro inválido, registro sumido) não tenta de novo: falha na hora, explícito.
class Crm::FollowUps::OptOutDecisionJob < ApplicationJob
  queue_as :low

  TRANSIENT_DB_ERRORS = [
    ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout, ActiveRecord::ConnectionNotEstablished, ActiveRecord::QueryCanceled
  ].freeze

  retry_on Crm::Ai::ResponsesClient::Error, Crm::Ai::OptOutClassifier::InvalidAnswer, *TRANSIENT_DB_ERRORS,
           wait: :polynomially_longer, attempts: 5 do |job, error|
    job.decision&.record_failure('falhou', error)
  end

  discard_on Crm::Ai::OptOutClassifier::Unavailable do |job, error|
    job.decision&.record_failure(error.message, error)
  end

  def perform(_card_id, _message_id)
    decision&.perform
  end

  # Público: os blocos de `retry_on`/`discard_on` gravam a falha por ele.
  def decision
    card_id, message_id = arguments
    card = Crm::Card.find_by(id: card_id)
    message = Message.find_by(id: message_id)
    return if card.blank? || message.blank?

    Crm::FollowUps::OptOutDecision.new(card: card, message: message)
  end
end
