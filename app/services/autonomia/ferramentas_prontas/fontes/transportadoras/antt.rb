# O RNTRC na base baixada (#2858, F5): pelo número (um registro), pelo CNPJ (a empresa pode ter mais de um) ou pelo nome
# (todas as palavras, cada uma pelo começo, sem acento e sem caixa: só empresa e cooperativa têm nome), no máximo `MAXIMO`.
class Autonomia::FerramentasProntas::Fontes::Transportadoras::Antt < Autonomia::FerramentasProntas::Bases::Provedor
  NOME = 'antt'.freeze
  BASE = 'transportadoras'.freeze
  MAXIMO = 10

  def buscar(_consulta, params)
    escopo = da_base(Autonomia::FerramentasProntas::Bases::Transportador)
    com_data(listar(filtrar(escopo, params).order(:nome, :rntrc), 'registros', MAXIMO) { |item| registro(item) })
  end

  private

  def filtrar(escopo, params)
    return escopo.where(rntrc: params['rntrc']) if params['rntrc']
    return escopo.where(cnpj: params['cnpj']) if params['cnpj']

    Autonomia::FerramentasProntas::Lista.comparavel(params.fetch('nome')).split.inject(escopo) do |achados, palavra|
      achados.where('nome_busca LIKE ?', "% #{ActiveRecord::Base.sanitize_sql_like(palavra)}%")
    end
  end

  def registro(item)
    {
      'rntrc' => item.rntrc, 'situacao' => item.situacao, 'categoria' => item.categoria, 'nome' => item.nome,
      'cnpj' => cnpj_formatado(item.cnpj), 'municipio' => item.municipio, 'uf' => item.uf, 'cadastrado_em' => item.cadastrado_em&.iso8601,
      'situacao_desde' => item.situacao_desde&.iso8601, 'equiparado' => item.equiparado
    }.compact
  end
end
