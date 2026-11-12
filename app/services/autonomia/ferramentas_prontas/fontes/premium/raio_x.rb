# RAIO-X DA EMPRESA (#2858, F7, Premium): o que a base da BigDataCorp sabe de uma empresa pelo CNPJ (`/empresas`):
# processos, sanções, crescimento, grupo econômico e obras. Ficam de fora, por desenho: as partes dos processos (nomes
# de pessoas), pessoa exposta politicamente e doação eleitoral (política), e os sócios pessoa física do grupo.
module Autonomia::FerramentasProntas::Fontes::Premium::RaioX
  Premium = Autonomia::FerramentasProntas::Premium
  Extrair = Premium::Extrair
  POR_CNPJ = ->(params) { "doc{#{params['cnpj']}}" }
  ROTA = '/empresas'.freeze
  MAX_EMPRESAS_DO_GRUPO = 10
  TIPO_EMPRESA = 'CNPJ'.freeze

  PROCESSOS = lambda do |dado|
    resumo = Extrair.ajustar(Extrair.campos(dado, primeiro: 'FirstLawsuitDate', ultimo: 'LastLawsuitDate', ultimos_30_dias: 'Last30DaysLawsuits',
                                                  ultimos_365_dias: 'Last365DaysLawsuits'), datas: %w[primeiro ultimo])
    lista = Array(dado['Lawsuits'])
    processos = Extrair.itens(lista, numero: 'Number', tribunal: 'CourtName', tipo: 'Type', assunto: 'MainSubject',
                                     situacao: 'Status', valor_da_causa: 'Value', ultima_movimentacao: 'LastMovementDate')
                       .map { |processo| Extrair.ajustar(processo, datas: %w[ultima_movimentacao], positivos: %w[valor_da_causa]) }
    Extrair.sem_vazio({ 'total' => lista.size }.merge(resumo).merge('processos' => processos))
  end

  SANCOES = lambda do |dado|
    resumo = Extrair.campos(dado, sancionada_hoje: 'IsCurrentlySanctioned', ja_foi_sancionada: 'WasPreviouslySanctioned',
                                  ultima_sancao: 'LastSanctionDate', sancoes_no_ultimo_ano: 'Last365DaysSanctions')
    resumo = Extrair.ajustar(resumo, datas: %w[ultima_sancao])
    lista = Extrair.itens(dado['SanctionsHistory'], fonte: 'Source', tipo: 'StandardizedSanctionType', inicio: 'StartDate',
                                                    fim: 'EndDate', ainda_na_lista: 'IsCurrentlyPresentOnSource')
                   .map { |sancao| Extrair.ajustar(sancao, datas: %w[inicio fim]) }
    Extrair.sem_vazio(resumo.merge('sancoes' => lista))
  end

  CRESCIMENTO = lambda do |dado|
    Extrair.sem_vazio(Extrair.campos(
                        dado, crescimento_1_ano: 'YearOverYearGrowthRateStatus1YearAgo', crescimento_3_anos: 'YearOverYearGrowthRateStatus3YearsAgo',
                              crescimento_5_anos: 'YearOverYearGrowthRateStatus5YearsAgo', funcionarios: 'AverageQtyEmployees',
                              funcionarios_1_ano_atras: 'AverageQtyEmployees1YearAgo', capital: 'AverageCapital',
                              capital_1_ano_atras: 'AverageCapital1YearAgo', filiais: 'AverageQtySubsidiaries'
                      ))
  end

  # Só as empresas do grupo (CNPJ). Pessoa física entra só na contagem.
  GRUPO = lambda do |dado|
    empresas = Array(dado['CurrentRelationships']).select { |item| item.is_a?(Hash) && item['RelatedEntityTaxIdType'] == TIPO_EMPRESA }
    lista = Extrair.itens(empresas, { nome: 'RelatedEntityName', cnpj: 'RelatedEntityTaxIdNumber', relacao: 'RelationshipName' },
                          maximo: MAX_EMPRESAS_DO_GRUPO)
    resumo = Extrair.campos(dado, empresas_no_grupo: 'TotalCompaniesRelationships', pessoas_no_grupo: 'TotalPeopleRelationships')
    Extrair.sem_vazio(resumo.merge('empresas' => lista))
  end

  OBRAS = lambda do |dado|
    resumo = Extrair.campos(dado, total: 'TotalNumberOfRecords', ativas: 'TotalNumberOfActiveRecords',
                                  terminadas: 'TotalNumberOfFinishedRecords')
    lista = Extrair.itens(dado['Records'], cno: 'CNO', cidade: 'City', uf: 'State', situacao: 'Status', inicio: 'StartDate',
                                           area: 'Area', tipo: 'Typology')
                   .map { |obra| Extrair.ajustar(obra, datas_americanas: %w[inicio]) }
    Extrair.sem_vazio(resumo.merge('obras' => lista))
  end

  # Custo e preço da 1ª faixa: R$ 0,06 -> R$ 0,09, salvo os processos (R$ 0,08 -> R$ 0,12). `prazo`: o dos processos
  # (`Dataset::PRAZO_DAS_LENTAS`, #2946); as outras, o da base.
  def self.consulta(nome, descricao, dataset, resposta, extrair, custo: '0.06', preco: '0.09', prazo: nil) # rubocop:disable Metrics/ParameterLists
    Premium::ConsultaPaga.new(
      nome: nome, descricao: descricao, obrigatorios: [Premium::Parametros::CNPJ],
      dataset: Premium::Dataset.new(nome: dataset, rota: ROTA, resposta: resposta, custo: custo, preco: preco, busca: POR_CNPJ,
                                    extrair: extrair, prazo: prazo)
    )
  end

  # Todas as consultas do card; a `FONTE` oferece só as que a BigDataCorp responde hoje (`Fonte#consultas`).
  CONSULTAS = [
    consulta('processos', 'processos judiciais e administrativos', 'processes', 'Lawsuits', PROCESSOS,
             custo: '0.08', preco: '0.12', prazo: Premium::Dataset::PRAZO_DAS_LENTAS),
    consulta('sancoes', 'sanções e listas restritivas', 'kyc', 'KycData', SANCOES),
    consulta('crescimento', 'como a empresa cresceu (funcionários e capital)', 'company_evolution', 'CompanyEvolutionData', CRESCIMENTO),
    consulta('grupo_economico', 'as empresas do mesmo grupo', 'economic_group_relationships', 'EconomicGroupRelationship', GRUPO),
    consulta('obras', 'obras de construção civil registradas', 'civil_construction_data', 'CivilConstructionData', OBRAS)
  ].freeze

  FONTE = Autonomia::FerramentasProntas::Fonte.new(
    chave: 'raio_x_empresa', slug: 'pronta_raio_x_empresa', nome: 'Raio-X da empresa',
    descricao: 'Consulta paga: o que uma base de dados empresarial sabe de uma empresa pelo CNPJ. Use só a consulta ' \
               'que responde à pergunta. Não traz dados de sócios pessoa física, de política nem de crédito.',
    consultas: CONSULTAS,
    limite_diario: nil, flag: Premium::FLAG,
    termos: 'BigDataCorp (contrato da plataforma). Base própria dela, por CNPJ.'
  )
end
