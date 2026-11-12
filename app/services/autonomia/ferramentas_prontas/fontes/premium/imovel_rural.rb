# IMÓVEL RURAL (#2858, F7, Premium): o cadastro do imóvel no CAR, pelo código do recibo (`sicar_property_data`), e o
# embargo do IBAMA da empresa dona, pelo CNPJ (`ondemand_ibama_embargados_company`). A BigDataCorp não acha o CAR pelo
# documento do dono, e o embargo de pessoa física fica fora desta fase (nome do dataset não confirmado).
module Autonomia::FerramentasProntas::Fontes::Premium::ImovelRural
  Premium = Autonomia::FerramentasProntas::Premium
  Extrair = Premium::Extrair

  CAR = lambda do |dado|
    reserva = dado['LegalReserve'].is_a?(Hash) ? Extrair.valor(dado['LegalReserve']['Total de reserva legal declarada']) : nil
    Extrair.sem_vazio(Extrair.campos(dado, codigo: 'PropertyCode', situacao: 'RegistrationStatus', condicao: 'RegistrationCondition',
                                           cidade: 'City', uf: 'UF', area_ha: 'AreaInHa', modulos_fiscais: 'TaxModulesInHa')
                             .merge('reserva_legal_ha' => reserva))
  end

  EMBARGO = lambda do |dado|
    certidao = Array(dado).find { |item| item.is_a?(Hash) }
    situacao = certidao && Extrair.valor(certidao['BaseStatus'])
    return nil if situacao.nil?

    extra = certidao['AdditionalOutputData'].is_a?(Hash) ? certidao['AdditionalOutputData'] : {}
    embargos = extra['Embargo'].is_a?(Hash) ? extra['Embargo'].values : Array(extra['Embargo'])
    lista = Extrair.itens(embargos, numero: 'Number', cidade: 'AreaCity', uf: 'AreaUF', desde: 'IssuedDate')
                   .map { |embargo| Extrair.ajustar(embargo, datas: %w[desde]) }
    Extrair.sem_vazio({ 'situacao' => situacao, 'embargos' => lista })
  end

  # Todas as consultas do card; a `FONTE` oferece só as que a BigDataCorp responde hoje (`Fonte#consultas`). Desde 12/11
  # (#2946), o embargo do IBAMA está fora (dataset "desligado" na BigDataCorp), e com ele o CNPJ: o card só aceita o
  # código do recibo do CAR.
  CONSULTAS = [
    Premium::ConsultaPaga.new(
      nome: 'car', descricao: 'a situação do imóvel no Cadastro Ambiental Rural, pelo código que está no recibo do CAR',
      obrigatorios: [Premium::Parametros::CODIGO_CAR],
      dataset: Premium::Dataset.new(nome: 'sicar_property_data', rota: '/enderecos', resposta: 'SicarProperty', custo: '0.10',
                                    preco: '0.15', busca: ->(params) { "carnumber{#{params['codigo_car']}}" }, extrair: CAR)
    ),
    Premium::ConsultaPaga.new(
      nome: 'embargo_ibama', descricao: 'se a empresa tem área embargada pelo IBAMA', obrigatorios: [Premium::Parametros::CNPJ],
      dataset: Premium::Dataset.new(nome: 'ondemand_ibama_embargados_company', rota: '/ondemand', resposta: 'OnlineCertificates',
                                    custo: '0.15', preco: '0.23', busca: ->(params) { "doc{#{params['cnpj']}}" }, extrair: EMBARGO)
    )
  ].freeze

  # A descrição não lista as consultas: o modelo as lê na ferramenta, que acompanha `Premium::DESLIGADAS_NA_FONTE`.
  FONTE = Autonomia::FerramentasProntas::Fonte.new(
    chave: 'imovel_rural', slug: 'pronta_imovel_rural', nome: 'Imóvel rural',
    descricao: 'Consulta paga: confere um imóvel rural, só com as consultas desta ferramenta.',
    consultas: CONSULTAS,
    limite_diario: nil, flag: Premium::FLAG,
    termos: 'BigDataCorp (contrato da plataforma). CAR pelo código do recibo; embargo do IBAMA pelo CNPJ.'
  )
end
