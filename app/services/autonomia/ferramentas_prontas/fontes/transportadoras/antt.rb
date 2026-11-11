# O RNTRC na base baixada (#2858, F5): pelo número (um registro) ou pelo CNPJ (a empresa pode ter mais de um).
class Autonomia::FerramentasProntas::Fontes::Transportadoras::Antt < Autonomia::FerramentasProntas::Bases::Provedor
  NOME = 'antt'.freeze
  BASE = 'transportadoras'.freeze
  MAXIMO = 10

  def consultar(_consulta, params)
    exigir_base!
    escopo = Autonomia::FerramentasProntas::Bases::Transportador.vigente
    escopo = params['rntrc'] ? escopo.where(rntrc: params['rntrc']) : escopo.where(cnpj: params.fetch('cnpj'))
    com_data(listar(escopo.order(:rntrc), 'registros', MAXIMO) { |item| registro(item) })
  end

  private

  def registro(item)
    {
      'rntrc' => item.rntrc, 'situacao' => item.situacao, 'categoria' => item.categoria, 'nome' => item.nome,
      'cnpj' => item.cnpj, 'municipio' => item.municipio, 'uf' => item.uf, 'cadastrado_em' => item.cadastrado_em&.iso8601,
      'situacao_desde' => item.situacao_desde&.iso8601, 'equiparado' => item.equiparado
    }.compact
  end
end
