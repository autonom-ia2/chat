# A geração distribuída da ANEEL na base baixada (#2858, F5), somada no CEP ou no município (o código IBGE da sede, pela
# tabela dos municípios). Sem nenhum sistema: não encontrado.
class Autonomia::FerramentasProntas::Fontes::GeracaoSolar::Aneel < Autonomia::FerramentasProntas::Bases::Provedor
  NOME = 'aneel'.freeze
  BASE = 'geracao_solar'.freeze

  def consultar(consulta, params)
    exigir_base!
    onde, escopo = consulta.nome == 'cep' ? no_cep(params) : na_cidade(params)
    total = escopo.sum(:quantidade)
    raise NaoEncontrado if total.zero?

    com_data(onde.merge('sistemas' => total, 'potencia_kw' => escopo.sum(:potencia_kw).to_f.round(2),
                        'por_tipo' => contagem(escopo, :tipo),
                        'por_classe' => contagem(escopo, :classe).transform_keys { |classe| classe || 'outra' }))
  end

  private

  # Quantos sistemas em cada valor da coluna, do maior para o menor.
  def contagem(escopo, coluna)
    escopo.group(coluna).sum(:quantidade).sort_by { |_valor, quantidade| -quantidade }.to_h
  end

  def modelo
    Autonomia::FerramentasProntas::Bases::GeracaoDistribuida.vigente
  end

  def no_cep(params)
    [{ 'cep' => params.fetch('cep') }, modelo.where(cep: params.fetch('cep'))]
  end

  def na_cidade(params)
    municipio = Autonomia::FerramentasProntas::Municipios.buscar(params.fetch('uf'), params.fetch('cidade'))
    raise NaoEncontrado if municipio.nil?

    [{ 'cidade' => municipio.nome, 'uf' => municipio.uf }, modelo.where(codigo_municipio: municipio.codigo)]
  end
end
