# A releitura do pedido de pessoa da IA do CRM antes da entrega (#1975), fora da rodada da fila: a chamada leva de 3
# a 74 s (backteste do PR #1980), e a rodada da fila (Crm::Ai::HandoffDrainJob) tem 45 s por passo. Quem enfileira e
# aplica é Crm::Ai::RevalidacaoNaFila; `token` é o `revalidando_desde` da marca, e o job de uma releitura que já não
# existe não chama a IA.
class Crm::Ai::RevalidaPassagemJob < ApplicationJob
  queue_as :low

  # Sem nova tentativa paga: um erro fora da chamada (a da IA já vira "falhou" e entrega) deixa a releitura em curso,
  # e a fila entrega como hoje quando ela passa de 10 min (Crm::Ai::RevalidacaoNaFila::VENCE_DEPOIS).
  discard_on StandardError do |job, error|
    Rails.logger.error("[crm][handoff] releitura descartada conversa=#{job.arguments.first} erro=#{error.class}")
  end

  def perform(conversation_id, token)
    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.blank?

    Crm::Ai::RevalidacaoNaFila.new(conversation).reler!(token)
  end
end
