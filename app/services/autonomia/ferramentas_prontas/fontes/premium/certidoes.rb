# CERTIDÕES DA EMPRESA (#2858, F7, Premium): as certidões que a BigDataCorp emite na hora, na fonte oficial, pelo CNPJ.
# Cada uma é um dataset sob demanda (`/ondemand`), cobrado à parte. A resposta leva só a situação e as datas: nem o
# texto, nem o PDF, nem o link do arquivo.
module Autonomia::FerramentasProntas::Fontes::Premium::Certidoes
  Premium = Autonomia::FerramentasProntas::Premium
  Extrair = Premium::Extrair
  POR_CNPJ = ->(params) { "doc{#{params['cnpj']}}" }
  ROTA = '/ondemand'.freeze

  def self.certidao(nome, descricao, dataset, custo, preco)
    Premium::ConsultaPaga.new(
      nome: nome, descricao: descricao, obrigatorios: [Premium::Parametros::CNPJ],
      dataset: Premium::Dataset.new(nome: dataset, rota: ROTA, resposta: 'OnlineCertificates', custo: custo, preco: preco,
                                    busca: POR_CNPJ, extrair: ->(dado) { Extrair.certidao(dado) })
    )
  end

  # O CADIN volta como consulta (`OnlineQuery`), com o resultado num texto da própria fonte.
  CADIN = Premium::ConsultaPaga.new(
    nome: 'cadin', descricao: 'se a empresa está no CADIN, o cadastro de quem deve a órgãos federais',
    obrigatorios: [Premium::Parametros::CNPJ],
    dataset: Premium::Dataset.new(
      nome: 'ondemand_cadin_company', rota: ROTA, resposta: 'OnlineQuery', custo: '0.10', preco: '0.15', busca: POR_CNPJ,
      extrair: lambda do |dado|
        consulta = Array(dado).find { |item| item.is_a?(Hash) }
        Extrair.sem_vazio(Extrair.campos(consulta && consulta['QueryResultData'], resultado: 'Content', uf: 'State'))
      end
    )
  )

  FONTE = Autonomia::FerramentasProntas::Fonte.new(
    chave: 'certidoes_empresa', slug: 'pronta_certidoes_empresa', nome: 'Certidões da empresa',
    descricao: 'Consulta paga: tira na hora, na fonte oficial, uma certidão de uma empresa pelo CNPJ e diz a situação. ' \
               'Use uma consulta por certidão pedida. Só empresa: não consulta pessoa física.',
    consultas: [
      certidao('divida_uniao', 'dívida com a União (PGFN)', 'ondemand_pgfn_company', '0.10', '0.15'),
      certidao('trabalhista', 'débitos trabalhistas (certidão do TST)', 'ondemand_cert_labor_debt_absence_company', '0.10', '0.15'),
      certidao('fgts', 'regularidade do FGTS (Caixa)', 'ondemand_fgts_company', '0.04', '0.06'),
      certidao('cnj', 'improbidade administrativa (certidão do CNJ)', 'ondemand_cnj_negative_certificate_company', '0.10', '0.15'),
      CADIN
    ],
    limite_diario: nil, flag: Premium::FLAG,
    termos: 'BigDataCorp (contrato da plataforma, repasse liberado pelo advogado). Certidões sob demanda, por CNPJ.'
  )
end
