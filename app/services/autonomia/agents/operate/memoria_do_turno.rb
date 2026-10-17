# Os blocos de memória do turno (#1601/#1755), para o principal (Responder) e para o especialista (Specialists::Runner).
# Só com a Fase 2 e a flag `memoria_ia` da conta (lida pelo ponto único `Crm::Memoria.ligada?`); sem uma delas, os
# blocos ficam vazios e o pedido ao modelo sai byte a byte como antes.
#
# A leitura é do CRM (`Crm::Memoria::Leitor`); a montagem no pedido é `PromptParts::Memoria`. Se a leitura falhar, o
# turno segue sem memória (o cliente não fica sem resposta por causa dela) e o erro vai ao rastreador com a conta.
module Autonomia::Agents::Operate::MemoriaDoTurno
  module_function

  # finalidade: :responder (o principal) ou :especialista (a cotação). -> PromptParts::Memoria::Blocos
  def blocos(conversation:, agent:, finalidade:)
    vazio = ::Autonomia::Agents::PromptParts::Memoria::Blocos.vazio
    return vazio unless ligada?(conversation)

    leitura = ::Crm::Memoria::Leitor.para(finalidade: finalidade, account: conversation.account, conversation: conversation,
                                          agent: agent)
    ::Autonomia::Agents::PromptParts::Memoria.montar(leitura, conversation: conversation)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: conversation&.account).capture_exception
    vazio
  end

  # Os itens do especialista (#1755): o "antes" e os fatos como dado (`user`, com cerca), o estado dito pelo sistema como
  # `developer`, para ir antes do pedido do atendente. [] fora de uma conversa (o Testar), sem a Fase 2 ou sem a flag.
  def itens_do_especialista(conversation:, agent:)
    return [] if conversation.nil?

    memoria = blocos(conversation: conversation, agent: agent, finalidade: :especialista)
    [['user', memoria.antes], ['developer', memoria.sistema], ['user', memoria.fatos]].filter_map do |papel, texto|
      ::Autonomia::Agents::PromptParts::Mensagem.montar(papel, texto) if texto.present?
    end
  end

  def ligada?(conversation)
    account = conversation&.account
    account.present? && ::Autonomia::Agents::Fase2.ligada?(account) && ::Crm::Memoria.ligada?(account)
  end
end
