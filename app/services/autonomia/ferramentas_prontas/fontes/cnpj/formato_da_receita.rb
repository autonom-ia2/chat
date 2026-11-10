# O formato da base pública da Receita, que a BrasilAPI e a Minha Receita devolvem igual. Quem inclui define `caminho`.
module Autonomia::FerramentasProntas::Fontes::Cnpj::FormatoDaReceita
  CAMPOS = {
    razao_social: 'razao_social', nome_fantasia: 'nome_fantasia', situacao: 'descricao_situacao_cadastral',
    data_da_situacao: 'data_situacao_cadastral', abertura: 'data_inicio_atividade', natureza_juridica: 'natureza_juridica',
    porte: 'porte', cidade: 'municipio', uf: 'uf'
  }.freeze

  def consultar(_consulta, params)
    dado = objeto!(get(caminho(params['cnpj'])))
    Autonomia::FerramentasProntas::Fontes::Cnpj.enxuto(
      params['cnpj'], dado, campos: CAMPOS,
                            atividade: { 'codigo' => dado['cnae_fiscal'], 'descricao' => dado['cnae_fiscal_descricao'] }
    )
  end
end
