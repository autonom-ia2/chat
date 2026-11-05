# card.parado (#2499, PR3): os cards abertos na etapa escolhida que entraram nela entre `dias + janela` e `dias`
# atrás. Usa o índice (account_id, entered_stage_at). O card que já tinha passado do prazo havia mais de 1 dia quando
# a automação foi ligada nunca dispara: ligar não age no passado. Se o card sair da etapa e voltar, o instante de
# entrada muda, e a marca também.
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
    limite = @agora - @gatilho['dias'].to_i.days
    ::Crm::Card.where(account_id: @definicao.account_id, stage_id: @gatilho['etapa_id'], status: :open)
               .where(entered_stage_at: (limite - ::Autonomia::Automacao::Tempo::JANELA)..limite)
  end
end
