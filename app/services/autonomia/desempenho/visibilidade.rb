# O que cada pessoa pode ver do painel (#2251), depois de montado:
# - Quem vê só parte das caixas já recebe o painel montado só com as conversas delas (Painel, ESPEC 6.2). Aqui fica a
#   marca `meta.visibilidade` com `escopo: 'caixas'` e quantas procuras do período ficaram de fora (`ocultas`), para a
#   tela avisar que os números são das caixas da pessoa; o ticket (da conta inteira) não vai.
# - Valor de venda em dinheiro (o ticket e o ganho em R$ das sugestões) segue `sales_value_view`, como no CRM (#2075,
#   Crm::ValorDeVenda); sem ela, as contagens ficam.
class Autonomia::Desempenho::Visibilidade
  # `ocultas`: nil para quem vê todas as caixas; senão, as procuras do período de caixas que a pessoa não vê.
  # `ve_valores`: Crm::ValorDeVenda.ve?.
  def initialize(ocultas:, ve_valores: true)
    @ocultas = ocultas
    @ve_valores = ve_valores
  end

  def aplicar(painel)
    sem_valores(com_escopo(painel))
  end

  private

  def com_escopo(painel)
    return painel if @ocultas.nil?

    meta = painel['meta']
    visibilidade = meta['visibilidade'].merge('escopo' => 'caixas', 'ocultas' => @ocultas)
    # O ticket é do histórico da conta inteira: quem vê só parte das caixas não o recebe, como as sugestões.
    painel.merge('meta' => meta.merge('visibilidade' => visibilidade), 'ticket' => nil)
  end

  def sem_valores(painel)
    return painel if @ve_valores

    sugestoes = Array(painel['recomendacoes']).map do |cartao|
      cartao['ganho'] ? cartao.merge('ganho' => cartao['ganho'].merge('valor' => nil)) : cartao
    end
    painel.merge('ticket' => nil, 'recomendacoes' => sugestoes)
  end
end
