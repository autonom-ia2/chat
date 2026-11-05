# card.parado (#2499, PR3): os cards abertos na etapa escolhida que entraram nela entre `dias + janela` e `dias`
# atrás. Usa o índice (account_id, entered_stage_at). Ligar não age no passado: o card que chegou ao prazo antes de
# a automação ser ligada não dispara; só os que chegam ao prazo dali em diante. Se o card sair da etapa e voltar, o
# instante de entrada muda, e a marca também.
class Autonomia::Automacao::Tempo::Parado
  def initialize(definicao:, gatilho:, agora:)
    @definicao = definicao
    @gatilho = gatilho
    @agora = agora
  end

  # Cada card da janela, com a marca do fato.
  def cada
    escopo.find_each { |card| yield card, ::Autonomia::Automacao::Gatilhos.marca_do_parado(card) }
  end

  def escopo
    dias = @gatilho['dias'].to_i.days
    limite = @agora - dias
    inicio = [limite - ::Autonomia::Automacao::Tempo::JANELA, ::Autonomia::Automacao::Tempo.ligada_desde(@definicao) - dias].max
    ::Crm::Card.where(account_id: @definicao.account_id, stage_id: @gatilho['etapa_id'], status: :open)
               .where(entered_stage_at: inicio..limite)
  end
end
