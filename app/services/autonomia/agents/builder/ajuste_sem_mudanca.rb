# #2984 — o AJUSTE fora da Fase 2 (o caminho de todas as contas que não estão no piloto): a escrita que não muda nada
# no agente, ou que não venceu, não fecha como aplicada. Sem isto o turno terminava com `applied: true` e a tela
# mostrava "Pronto" para um pedido que não entrou. Ao dono vai só texto fixo, nunca um texto do modelo que afirme ter
# mudado. O texto é o `sem_pedido` da Fase 2 ("não encontrei uma mudança para fazer"), e não o `sem_mudanca` ("já estava
# assim"): aqui não há lista de pedidos para saber se o dono pediu o que o agente já fazia ou algo que o Construtor não
# muda.
module Autonomia::Agents::Builder::AjusteSemMudanca
  private

  # O turno é o ajuste de um agente que já saiu do rascunho e a escrita não teve efeito. Quem diz se alguma coluna mudou
  # é a própria escrita, sob a trava do agente (`Agent#escrita_do_construtor_mudou?`). A criação fica de fora, e o
  # rascunho que já tem instrução também: ali o turno ainda é da criação (o dono voltou um passo e avançou de novo para
  # a revisão), e segurar a conversa aberta o prenderia na entrevista.
  def ajuste_sem_efeito?(agent, aplicada)
    return false if criacao? || agent.draft?

    aplicada != true || !agent.escrita_do_construtor_mudou?
  end

  # O turno fica aberto, com o aviso fixo. A marca `aviso_fixo` guarda o texto para ele não virar pergunta pendente
  # (`BuildThread.aviso_fixo?`). Token perdido: outra geração desta conversa é dona do turno, nada a marcar.
  def fechar_ajuste_sem_efeito!(token, parsed, aplicada)
    texto = aplicada == true ? texto_do_ajuste(:sem_pedido) : texto_da_escrita_perdida(token)
    return if texto.nil?

    @closed = false
    estado = estado_do_turno(parsed.merge('needs_more_info' => true, 'next_question' => texto))
             .merge('applied' => false, 'truncated_fields' => [], 'aviso_fixo' => texto)
    persist_assistant_turn!(texto) if @thread.mark_ready!(token, state: estado)
  end

  def texto_da_escrita_perdida(token)
    case motivo_da_escrita_perdida(token)
    when :apagado then texto_do_ajuste(:agente_apagado)
    when :superado then texto_do_ajuste(:superado)
    end
  end
end
