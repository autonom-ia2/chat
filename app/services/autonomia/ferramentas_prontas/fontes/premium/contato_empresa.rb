# CONTATO E MERCADO DE EMPRESAS (#2858, F7, Premium): telefone e e-mail de uma EMPRESA pelo CNPJ (`phones_extended`,
# `emails_extended`) e quantas empresas há numa região pelo CEP (`companies_statistics`, só números, sem a lista). Regra
# "QI 70": o CEP da região sai da rua e da cidade (`pelo_endereco`), como no risco do endereço; só a cidade não basta.
# Contato de pessoa física fica de fora por desenho: o único documento aceito é o CNPJ (um CPF não passa no dígito do
# CNPJ, e a BigDataCorp nem é chamada). Telefone na lista "não perturbe" e e-mail marcado como pessoal não saem.
# Telefone que a base marca como inativo (`IsActive: false`) SAI, com `pode_estar_desatualizado`, depois dos ativos
# (decisão do Rodrigo, 14/11, #3015): na base real é o comum, até no telefone principal (10 de 11 numa empresa grande).
module Autonomia::FerramentasProntas::Fontes::Premium::ContatoEmpresa
  Premium = Autonomia::FerramentasProntas::Premium
  Extrair = Premium::Extrair
  POR_CNPJ = ->(params) { "doc{#{params['cnpj']}}" }
  MAX_CONTATOS = 3
  PESSOAL = 'personal'.freeze
  # O CNPJ que a base recusa é `documento_invalido`; aqui a base aceitou e não tem telefone (#3015).
  SEM_TELEFONE = 'A consulta foi feita e a base não tem telefone desta empresa. Diga isso ao cliente sem sugerir que o ' \
                 'CNPJ está errado e, se ajudar, ofereça procurar o e-mail. Não invente.'.freeze
  # O formato do que os telefones guardam no cache do dia (`Consulta#versao_do_cache`): 2 desde o inativo com aviso
  # (#3015). O que foi guardado antes (só os ativos, ou "não havia registro") deixa de ser lido.
  VERSAO_DO_CACHE_DOS_TELEFONES = 2

  # Ordem: os ativos primeiro, e o principal antes dos outros; no empate, a ordem da base.
  TELEFONES = lambda do |dado|
    validos = Array(dado['Phones']).select { |fone| fone.is_a?(Hash) && fone['IsInDoNotCallList'] != true }
    em_ordem = validos.each_with_index.sort_by do |fone, posicao|
      [fone['IsActive'] == false ? 1 : 0, fone['IsMainForEntity'] == true ? 0 : 1, posicao]
    end
    lista = em_ordem.filter_map { |fone, _posicao| telefone(fone) }
    lista.empty? ? nil : { 'telefones' => lista.first(MAX_CONTATOS) }
  end

  # `pode_estar_desatualizado` só quando a base diz se o telefone está ativo.
  def self.telefone(fone)
    numero = [Extrair.valor(fone['AreaCode']), Extrair.valor(fone['Number'])].compact.join(' ').presence
    return unless numero

    campos = { 'telefone' => numero }.merge(Extrair.campos(fone, tipo: 'Type', principal: 'IsMainForEntity'))
    fone.key?('IsActive') ? campos.merge('pode_estar_desatualizado' => fone['IsActive'] == false) : campos
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
      nome: 'telefone',
      descricao: 'os telefones da empresa. O telefone com pode_estar_desatualizado: true pode não atender mais: passe ' \
                 'ao cliente com esse aviso',
      obrigatorios: [Premium::Parametros::CNPJ], nao_encontrado: SEM_TELEFONE,
      versao_do_cache: VERSAO_DO_CACHE_DOS_TELEFONES,
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
