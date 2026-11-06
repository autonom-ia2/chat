# O que cada pessoa pode ver do painel (#2251), depois de montado:
# - Quem vê só parte das caixas já recebe o painel montado só com as conversas delas (Painel, ESPEC 6.2). Aqui fica a
#   marca `meta.visibilidade` com `escopo: 'caixas'` e quantas procuras do período ficaram de fora (`ocultas`), para a
#   tela avisar que os números são das caixas da pessoa; o ticket (da conta inteira) não vai.
# - Valor de venda em dinheiro (o ticket e o ganho em R$ das sugestões) segue `sales_value_view`, como no CRM (#2075,
#   Crm::ValorDeVenda); sem ela, as contagens ficam.
# - O anúncio de origem (#2296) segue Crm::AnuncioDeOrigem.ve?, como no card e em Números: sem a chave, a origem não
#   lista os anúncios (id, nome e campanha), a procura vai sem `anuncio_id` e `origem.anuncios_ocultos` avisa a tela, o
#   PDF e a planilha para não abrirem o bloco "por anúncio". As sugestões da frente "anúncio" também não vão: são
#   escritas fora e falam do anúncio. Ficam as contagens de anúncio x sem anúncio, como o gasto.
class Autonomia::Desempenho::Visibilidade
  FRENTE_DO_ANUNCIO = 'anuncio'.freeze

  # `ocultas`: nil para quem vê todas as caixas; senão, as procuras do período de caixas que a pessoa não vê.
  # `ve_valores`: Crm::ValorDeVenda.ve?. `ve_anuncio`: Crm::AnuncioDeOrigem.ve?.
  def initialize(ocultas:, ve_anuncio:, ve_valores: true)
    @ocultas = ocultas
    @ve_valores = ve_valores
    @ve_anuncio = ve_anuncio
  end

  def aplicar(painel)
    sem_anuncio(sem_valores(com_escopo(painel)))
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

  def sem_anuncio(painel)
    return painel if @ve_anuncio

    origem = painel['origem'].is_a?(Hash) ? painel['origem'].merge('anuncios' => [], 'anuncios_ocultos' => true) : painel['origem']
    procuras = Array(painel['procuras']).map { |procura| procura.merge('anuncio_id' => nil) }
    sugestoes = Array(painel['recomendacoes']).reject { |cartao| cartao['frente'] == FRENTE_DO_ANUNCIO }
    painel.merge('origem' => origem, 'procuras' => procuras, 'recomendacoes' => sugestoes)
  end
end
