# A geração distribuída da ANEEL na base baixada (#2858, F5), somada no CEP ou no município (o código IBGE da sede, pela
# tabela dos municípios). Sem nenhum sistema: não encontrado.
# O total leva nome de total (`total_de_sistemas`, `potencia_total_kw`): com o mesmo nome do campo de cada classe, a tela
# do Experimente repetia "Sistemas instalados" três vezes. O detalhe por tipo de geração só vem com mais de um tipo:
# quase todo lugar é só solar, e "solar: o total" repete o total. Em cada classe, a potência vai ao agente, e a tela
# mostra só os sistemas ("Residencial: 16.577 · Comercial: 1.332"), porque `potencia_kw` não tem rótulo.
class Autonomia::FerramentasProntas::Fontes::GeracaoSolar::Aneel < Autonomia::FerramentasProntas::Bases::Provedor
  NOME = 'aneel'.freeze
  BASE = 'geracao_solar'.freeze

  def buscar(consulta, params)
    onde, escopo = consulta.nome == 'cep' ? no_cep(params) : na_cidade(params)
    total = escopo.sum(:quantidade)
    raise NaoEncontrado if total.zero?

    com_data(onde.merge('total_de_sistemas' => total, 'potencia_total_kw' => escopo.sum(:potencia_kw).to_f.round(2))
                 .merge(por_tipo(escopo)).merge('por_classe' => contagem(escopo, :classe)))
  end

  private

  def por_tipo(escopo)
    tipos = contagem(escopo, :tipo)
    tipos.size > 1 ? { 'por_tipo' => tipos } : {}
  end

  # Cada valor da coluna (o tipo, a classe), com quantos sistemas e a potência, do maior para o menor:
  # [{ 'nome' => 'Residencial', 'sistemas' => 2, 'potencia_kw' => 10.0 }, ...]. Classe vazia no arquivo: 'outra'.
  def contagem(escopo, coluna)
    somas = escopo.group(coluna).pluck(coluna, Arel.sql('SUM(quantidade)'), Arel.sql('SUM(potencia_kw)'))
    somas.sort_by { |_valor, sistemas, _potencia| -sistemas }.map do |valor, sistemas, potencia|
      { 'nome' => valor || 'outra', 'sistemas' => sistemas.to_i, 'potencia_kw' => potencia.to_f.round(2) }
    end
  end

  def modelo
    da_base(Autonomia::FerramentasProntas::Bases::GeracaoDistribuida)
  end

  def no_cep(params)
    [{ 'cep' => params.fetch('cep') }, modelo.where(cep: params.fetch('cep'))]
  end

  def na_cidade(params)
    municipio = Autonomia::FerramentasProntas::Municipios.buscar(params['uf'], params.fetch('cidade'))
    raise NaoEncontrado if municipio.nil?

    [{ 'cidade' => municipio.nome, 'uf' => municipio.uf }, modelo.where(codigo_municipio: municipio.codigo)]
  end
end
