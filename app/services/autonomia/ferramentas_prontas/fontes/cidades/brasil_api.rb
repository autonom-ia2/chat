# Estados e municípios na BrasilAPI (reserva; ela repassa o IBGE).
class Autonomia::FerramentasProntas::Fontes::Cidades::BrasilApi < Autonomia::FerramentasProntas::Provedor
  NOME = 'brasilapi'.freeze
  HOST = 'brasilapi.com.br'.freeze

  def consultar(consulta, params)
    return estados if consulta.nome == 'estados'

    uf = params.fetch('uf').upcase
    lista = lista!(get("/api/ibge/municipios/v1/#{uf}?providers=dados-abertos-br,gov"))
    nomes = lista.map { |item| exigir!(texto(objeto!(item)['nome'])) }
    Autonomia::FerramentasProntas::Fontes::Cidades.cidades(uf, exigir!(nomes))
  end

  private

  def estados
    itens = lista!(get('/api/ibge/uf/v1')).map do |item|
      { 'uf' => exigir!(texto(objeto!(item)['sigla'])), 'nome' => exigir!(texto(item['nome'])),
        'regiao' => texto(item.dig('regiao', 'nome')) }.compact
    end
    { 'estados' => exigir!(itens.sort_by { |item| Autonomia::FerramentasProntas::Ufs.comparavel(item['nome']) }) }
  end
end
