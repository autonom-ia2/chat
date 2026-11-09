# A conversa em que os passos "mensagem" e "avisar" agem (#2414 F4): o próprio alvo, ou a conversa principal quando o
# alvo é um card. Card sem conversa principal (e contato) usa a conversa que a receita abriu na caixa da conversa nova
# (#2680); sem ela, não tem onde mandar: o passo pula com `sem_conversa`, e o histórico mostra. Os valores do texto
# são lidos do alvo, pelas pontes (#2499): no card, `card.titulo` e a conversa principal.
module Autonomia::Automacao::NaConversa
  Resultado = ::Autonomia::Automacao::PassoDeAcao::Resultado

  def initialize(execucao:, passo:, alvo:)
    @execucao = execucao
    @passo = passo
    @alvo = alvo
    @conversa = ::Autonomia::Automacao::Contexto.de(alvo, execucao: execucao).conversa
  end

  private

  def sem_conversa = Resultado.new(tipo: :pulado, motivo: 'sem_conversa', dados: {})

  # Quem ligou precisa enxergar a conversa em que o passo age, e não só o alvo: no card, a pergunta vai à conversa
  # principal. Sem acesso, a automação pausa, como na ação (D1).
  def sem_acesso
    return if ::Autonomia::Automacao::Acesso.alcanca?(@execucao.automacao.ligada_por, @conversa)

    Resultado.new(tipo: :sem_acesso, motivo: 'quem_ligou_sem_acesso', dados: {})
  end

  def texto_pronto = ::Autonomia::Automacao::Texto.new(@passo['texto'], valores).montar

  # Com as permissões de quem ligou (#2597) e a execução: a reunião do gatilho (G12) sai da marca dela.
  def valores
    @valores ||= ::Autonomia::Automacao::Valores.new(alvo: ::Autonomia::Automacao::Contexto.de(@alvo, execucao: @execucao),
                                                     quem: @execucao.automacao.ligada_por)
  end

  # O texto ficou sem um valor: o link da agenda vazio diz por quê (G12); o resto é o faltou_valor de sempre.
  def faltou_valor
    por = valores.falta_da_agenda
    return Resultado.new(tipo: :pulado, motivo: ::Autonomia::Automacao::AgendaDeReserva.motivo(por), dados: { 'por' => por }) if por

    Resultado.new(tipo: :pulado, motivo: 'faltou_valor', dados: {})
  end

  def marca
    { automacao_id: @execucao.automacao_id, execucao_id: @execucao.id, passo: @passo['id'] }
  end
end
