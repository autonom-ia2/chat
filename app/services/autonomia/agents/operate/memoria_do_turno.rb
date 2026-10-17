# Os blocos de memória do turno (#1601/#1755), só para o agente PRINCIPAL criado na página de Agentes (o Responder:
# Clara, Hubber...). Decisões do Rodrigo (17/10/2026): os especialistas e ajudantes não leem a memória (recebem o que o
# principal manda a eles), e a Lia (Agente de Cotação, `insurance_quote`) fica de fora: é um agente construído à parte,
# e a estrutura dela não muda. Só com a Fase 2. A flag `memoria_ia` e a caixa fora da memória são do CRM: o `Crm::Memoria::Leitor` chama
# `Crm::Memoria.ativa?` por dentro e devolve a leitura vazia; com ela, o pedido ao modelo sai byte a byte como antes.
#
# Se a LEITURA falhar (o Leitor é código do CRM: banco, dado inesperado), o turno segue sem memória e o erro vai ao
# rastreador com a conta: a IA nunca fica muda nem a cotação some por causa da memória. A montagem do nosso lado
# (PromptParts::Memoria) não tem rescue: erro nela aparece nos specs.
module Autonomia::Agents::Operate::MemoriaDoTurno
  module_function

  # -> PromptParts::Memoria::Blocos
  def blocos(conversation:, agent:, finalidade: :responder)
    vazio = ::Autonomia::Agents::PromptParts::Memoria::Blocos.vazio
    return vazio if conversation.nil? || agent&.agent_type == 'insurance_quote'
    return vazio unless ::Autonomia::Agents::Fase2.ligada?(conversation.account)

    leitura = ler(conversation, agent, finalidade)
    leitura ? ::Autonomia::Agents::PromptParts::Memoria.montar(leitura, conversation: conversation) : vazio
  end

  def ler(conversation, agent, finalidade)
    ::Crm::Memoria::Leitor.para(finalidade: finalidade, account: conversation.account, conversation: conversation, agent: agent)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: conversation.account).capture_exception
    nil
  end
end
