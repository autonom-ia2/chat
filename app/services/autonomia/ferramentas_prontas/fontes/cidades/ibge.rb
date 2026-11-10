# Estados e municípios na API de localidades do IBGE (principal).
class Autonomia::FerramentasProntas::Fontes::Cidades::Ibge < Autonomia::FerramentasProntas::Provedor
  NOME = 'ibge'.freeze
  HOST = 'servicodados.ibge.gov.br'.freeze

  def consultar(consulta, params)
    return estados if consulta.nome == 'estados'

    uf = params.fetch('uf').upcase
    lista = lista!(get("/api/v1/localidades/estados/#{uf}/municipios",
                       max_bytes: Autonomia::FerramentasProntas::Fontes::Cidades::MAX_BYTES_IBGE))
    Autonomia::FerramentasProntas::Fontes::Cidades.cidades(uf, exigir!(lista.map { |item| exigir!(texto(objeto!(item)['nome'])) }))
  end

  private

  def estados
    itens = lista!(get('/api/v1/localidades/estados?orderBy=nome')).map do |item|
      { 'uf' => exigir!(texto(objeto!(item)['sigla'])), 'nome' => exigir!(texto(item['nome'])),
        'regiao' => texto(item.dig('regiao', 'nome')) }.compact
    end
    { 'estados' => exigir!(itens) }
  end
end
