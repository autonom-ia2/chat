# #2984 — o AJUSTE fora da Fase 2 (o caminho de todas as contas que não estão no piloto): a escrita que não muda nada
# no agente não fecha como aplicada. Sem isto o turno terminava com `applied: true` e a tela mostrava "Pronto" para um
# pedido que não entrou. É a regra 1 do ajuste da Fase 2 (AjusteConferido), com o mesmo texto fixo: ao dono nunca vai um
# texto do modelo que afirme ter mudado.
module Autonomia::Agents::Builder::AjusteSemMudanca
  private

  # O que a escrita do ajuste pode mudar no agente: igual antes e depois = nada mudou. nil na criação, onde não há
  # "antes" para comparar, e no rascunho que já tem instrução: ali o turno ainda é da criação (o dono voltou um passo e
  # avançou de novo para a revisão), e segurar a conversa aberta o prenderia na entrevista.
  def retrato_do_ajuste(agent)
    return if criacao? || agent.draft?

    Autonomia::Agents::Builder::AjustePorLista.comparavel(agent).merge('agent_type' => agent.agent_type)
  end

  # O turno fica aberto, com a pergunta fixa, como o da Fase 2 que não aplicou nada.
  def fechar_sem_mudanca!(token, parsed)
    @closed = false
    texto = texto_do_ajuste(:sem_pedido)
    estado = estado_do_turno(parsed.merge('needs_more_info' => true, 'next_question' => texto))
             .merge('applied' => false, 'truncated_fields' => [])
    persist_assistant_turn!(texto) if @thread.mark_ready!(token, state: estado)
  end
end
