# A lista das estações automáticas do INMET (fonte única). Vem inteira, sem parâmetro: a mais perto é calculada na
# `Estacoes.refinar`, sobre a lista da fonte ou do cache.
class Autonomia::FerramentasProntas::Fontes::Estacoes::Inmet < Autonomia::FerramentasProntas::Provedor
  NOME = 'inmet'.freeze
  HOST = 'apitempo.inmet.gov.br'.freeze

  def consultar(_consulta, _params)
    estacoes = Autonomia::FerramentasProntas::Fontes::Estacoes
    lista = lista!(get('/estacoes/T', max_bytes: estacoes::MAX_BYTES_INMET))
    { 'estacoes' => exigir!(lista.filter_map { |item| estacoes.estacao(item) }) }
  end
end
