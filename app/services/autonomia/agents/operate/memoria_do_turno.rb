# Os blocos de memória do turno (#1601/#1755), para o principal (Responder) e para o especialista (Specialists::Runner).
# Só com a Fase 2. A flag `memoria_ia` e a caixa fora da memória são do CRM: o `Crm::Memoria::Leitor` chama
# `Crm::Memoria.ativa?` por dentro e devolve a leitura vazia; com ela, o pedido ao modelo sai byte a byte como antes.
#
# Se a LEITURA falhar no banco, o turno segue sem memória (o cliente não fica sem resposta por causa dela) e o erro vai
# ao rastreador com a conta. Erro de código ou de contrato (a montagem) não é engolido: aparece.
module Autonomia::Agents::Operate::MemoriaDoTurno
  module_function

  # finalidade: :responder (o principal) ou :especialista (a cotação). -> PromptParts::Memoria::Blocos
  def blocos(conversation:, agent:, finalidade:)
    vazio = ::Autonomia::Agents::PromptParts::Memoria::Blocos.vazio
    return vazio unless conversation && ::Autonomia::Agents::Fase2.ligada?(conversation.account)

    leitura = ler(conversation, agent, finalidade)
    leitura ? ::Autonomia::Agents::PromptParts::Memoria.montar(leitura, conversation: conversation) : vazio
  end

  # Os itens do especialista (#1755): o "antes" e os fatos como dado (`user`, com cerca), o estado e a regra como
  # `developer`, para ir antes do pedido do atendente. Também anota no Delivery os ids enviados, para o `replied` do
  # principal registrar o que a cotação leu. [] fora de uma conversa (o Testar) ou sem memória.
  def itens_do_especialista(delivery:, agent:)
    return [] if delivery&.conversation.nil?

    memoria = blocos(conversation: delivery.conversation, agent: agent, finalidade: :especialista)
    delivery.anotar_memoria(memoria.ids)
    [['user', memoria.antes], ['developer', memoria.sistema], ['user', memoria.fatos]].filter_map do |papel, texto|
      ::Autonomia::Agents::PromptParts::Mensagem.montar(papel, texto) if texto.present?
    end
  end

  def ler(conversation, agent, finalidade)
    ::Crm::Memoria::Leitor.para(finalidade: finalidade, account: conversation.account, conversation: conversation, agent: agent)
  rescue ActiveRecord::ActiveRecordError => e
    ChatwootExceptionTracker.new(e, account: conversation.account).capture_exception
    nil
  end
end
