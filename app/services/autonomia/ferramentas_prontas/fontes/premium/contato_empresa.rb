# CONTATO E MERCADO DE EMPRESAS (#2858, F7, Premium): telefone e e-mail de uma EMPRESA pelo CNPJ (`phones_extended`,
# `emails_extended`) e quantas empresas há numa região pelo CEP (`companies_statistics`, só números, sem a lista). Regra
# "QI 70": o CEP da região sai da rua e da cidade (`pelo_endereco`), como no risco do endereço; só a cidade não basta.
# Contato de pessoa física fica de fora por desenho: o único documento aceito é o CNPJ (um CPF não passa no dígito do
# CNPJ, e a BigDataCorp nem é chamada). Telefone na lista "não perturbe" e e-mail marcado como pessoal não saem.
module Autonomia::FerramentasProntas::Fontes::Premium::ContatoEmpresa
  Premium = Autonomia::FerramentasProntas::Premium
  Extrair = Premium::Extrair
  POR_CNPJ = ->(params) { "doc{#{params['cnpj']}}" }
  MAX_CONTATOS = 3
  PESSOAL = 'personal'.freeze

  TELEFONES = lambda do |dado|
    validos = Array(dado['Phones']).select { |fone| fone.is_a?(Hash) && fone['IsInDoNotCallList'] != true && fone['IsActive'] != false }
    lista = validos.filter_map do |fone|
      numero = [Extrair.valor(fone['AreaCode']), Extrair.valor(fone['Number'])].compact.join(' ').presence
      numero && { 'telefone' => numero }.merge(Extrair.campos(fone, tipo: 'Type', principal: 'IsMainForEntity'))
    end
    lista.empty? ? nil : { 'telefones' => lista.first(MAX_CONTATOS) }
  end

  EMAILS = lambda do |dado|
    validos = Array(dado['Emails']).select { |email| email.is_a?(Hash) && email['Type'].to_s.downcase != PESSOAL }
    lista = Extrair.itens(validos, { email: 'EmailAddress', principal: 'IsMainForEntity' }, maximo: MAX_CONTATOS)
                   .select { |email| email['email'] }
    lista.empty? ? nil : { 'emails' => lista }
  end

  REGIAO = lambda do |dado|
    Extrair.sem_vazio(Extrair.campos(dado, empresas: 'TotalCompanies', ativas: 'TotalActiveCompanies', inativas: 'TotalInactiveCompanies',
                                           meis: 'TotalMEIs', no_simples: 'TotalSimplesCompanies', matrizes: 'TotalHeadquarter',
                                           filiais: 'TotalBranches', idade_media_anos: 'AverageCompanyAge', atividades: 'TotalUniqueCNAES'))
  end

  # Todas as consultas do card; a `FONTE` oferece só as que a BigDataCorp responde hoje (`Fonte#consultas`). Empresas na região
  # tem o prazo das lentas (`Dataset::PRAZO_DAS_LENTAS`, #2946).
  CONSULTAS = [
    Premium::ConsultaPaga.new(
      nome: 'telefone', descricao: 'os telefones da empresa', obrigatorios: [Premium::Parametros::CNPJ],
      dataset: Premium::Dataset.new(nome: 'phones_extended', rota: '/empresas', resposta: 'ExtendedPhones', custo: '0.06',
                                    preco: '0.09', busca: POR_CNPJ, extrair: TELEFONES)
    ),
    Premium::ConsultaPaga.new(
      nome: 'email', descricao: 'os e-mails da empresa', obrigatorios: [Premium::Parametros::CNPJ],
      dataset: Premium::Dataset.new(nome: 'emails_extended', rota: '/empresas', resposta: 'ExtendedEmails', custo: '0.06',
                                    preco: '0.09', busca: POR_CNPJ, extrair: EMAILS)
    ),
    Premium::ConsultaPaga.new(
      nome: 'empresas_na_regiao',
      descricao: 'quantas empresas há na região do CEP (só números). O número é da região do CEP, não da cidade inteira. ' \
                 'O cliente não precisa saber o CEP: sem ele, mande a rua e a cidade (o bairro e o número ajudam a ' \
                 'escolher o CEP da rua); o CEP geral da cidade não serve',
      obrigatorios: [], opcionais: [Premium::Parametros::NUMERO_LOCAL, *Premium::Parametros::PELO_ENDERECO], pelo_endereco: true,
      exige_rua: true,
      dataset: Premium::Dataset.new(nome: 'companies_statistics', rota: '/enderecos', resposta: 'CompaniesStatistics', custo: '0.06',
                                    preco: '0.09', busca: ->(params) { "zipcode{#{params['cep']}}" }, extrair: REGIAO,
                                    prazo: Premium::Dataset::PRAZO_DAS_LENTAS)
    )
  ].freeze

  FONTE = Autonomia::FerramentasProntas::Fonte.new(
    chave: 'contato_empresa', slug: 'pronta_contato_empresa', nome: 'Contato e mercado de empresas',
    descricao: 'Consulta paga: telefone ou e-mail de uma EMPRESA pelo CNPJ, ou quantas empresas há numa região pelo ' \
               'CEP. Só empresa: não existe consulta de telefone, e-mail ou endereço de pessoa física nem de parentes. ' \
               'Se pedirem, diga com educação que esse dado não é consultado aqui e não chame esta ferramenta.',
    consultas: CONSULTAS,
    limite_diario: nil, flag: Premium::FLAG,
    termos: 'BigDataCorp (contrato da plataforma). Só empresa; respeita a lista "não perturbe".'
  )
end
