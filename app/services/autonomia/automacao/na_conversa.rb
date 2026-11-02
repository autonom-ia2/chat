# A conversa em que os passos "mensagem" e "avisar" agem (#2414 F4): o próprio alvo, ou a conversa principal quando o
# alvo é um card. Card sem conversa principal (e contato) não tem onde mandar: o passo pula com `sem_conversa`, e o
# histórico mostra. Os valores do texto são lidos dessa conversa.
module Autonomia::Automacao::NaConversa
  Resultado = ::Autonomia::Automacao::PassoDeAcao::Resultado

  def initialize(execucao:, passo:, alvo:)
    @execucao = execucao
    @passo = passo
    @conversa = alvo.is_a?(::Crm::Card) ? alvo.primary_conversation : (alvo if alvo.is_a?(::Conversation))
  end

  private

  def sem_conversa = Resultado.new(tipo: :pulado, motivo: 'sem_conversa', dados: {})

  def texto_pronto = ::Autonomia::Automacao::Texto.new(@passo['texto'], ::Autonomia::Automacao::Valores.new(conversa: @conversa)).montar

  def marca
    { automacao_id: @execucao.automacao_id, execucao_id: @execucao.id, passo: @passo['id'] }
  end
end
