# O CNPJ na OpenCNPJ (segunda reserva), com formato próprio: a atividade principal é a marcada na lista `cnaes`.
class Autonomia::FerramentasProntas::Fontes::Cnpj::OpenCnpj < Autonomia::FerramentasProntas::Provedor
  NOME = 'opencnpj'.freeze
  HOST = 'api.opencnpj.org'.freeze
  CAMPOS = {
    razao_social: 'razao_social', nome_fantasia: 'nome_fantasia', situacao: 'situacao_cadastral',
    data_da_situacao: 'data_situacao_cadastral', abertura: 'data_inicio_atividade', natureza_juridica: 'natureza_juridica',
    porte: 'porte_empresa', cidade: 'municipio', uf: 'uf'
  }.freeze

  def consultar(_consulta, params)
    dado = objeto!(get("/#{params['cnpj']}"))
    principal = Array(dado['cnaes']).find { |cnae| cnae.is_a?(Hash) && cnae['is_principal'] } || {}
    Autonomia::FerramentasProntas::Fontes::Cnpj.enxuto(
      params['cnpj'], dado, campos: CAMPOS,
                            atividade: { 'codigo' => principal['codigo'] || dado['cnae_principal'], 'descricao' => principal['descricao'] }
    )
  end
end
