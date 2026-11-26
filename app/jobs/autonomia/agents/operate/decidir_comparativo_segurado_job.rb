# A DECISÃO DO COMPARATIVO SEGURADO (#3258), fora do turno: o turno que acabou de falar (a cadeia no último pedaço, ou o
# Responder com a resposta inteira ou o sinal de silêncio) só enfileira este job, com os ids
# (`ComparativoSegurado.decidir_depois`). Erro aqui não toca no turno nem no pedaço: sobe e o Sidekiq refaz este job. A
# decisão é idempotente (lock da âncora e estado gravado nela), então o job repetido não manda nada duas vezes.
class Autonomia::Agents::Operate::DecidirComparativoSeguradoJob < ApplicationJob
  # MEDIUM, junto do `EnviarCartoesJob`: é a mesma resposta ao cliente.
  queue_as :medium

  def perform(conversation_id, agent_id, reply_to_message_id)
    conversation = Conversation.find_by(id: conversation_id)
    agent = ::Autonomia::Agents::Agent.find_by(id: agent_id)
    return if conversation.nil? || agent.nil?

    ::Autonomia::Agents::Operate::ComparativoSegurado.no_fim_do_turno(conversation, agent, reply_to_message_id)
  end
end
