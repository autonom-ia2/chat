# RISCO DO ENDEREÇO (#2858, F7, Premium): para quem segura um imóvel. Pelo CEP e número: se o ponto está em área de
# comunidade do IBGE (`address_risk`), as estatísticas de crime da cidade (`criminal_statistics_data`, só SP, RJ e MG,
# por município — a BigDataCorp não tem por bairro) e a qualificação do imóvel pela vistoria da Rede Vistorias
# (`/marketplace`, `partner_rede_vistorias_address`; a que volta vazia não é cobrada pela BigDataCorp).
module Autonomia::FerramentasProntas::Fontes::Premium::RiscoEndereco
  Premium = Autonomia::FerramentasProntas::Premium
  Extrair = Premium::Extrair
  POR_CEP_E_NUMERO = ->(params) { "zipcode{#{params['cep']}},addressnumber{#{params['numero']}}" }
  LEGENDA_DA_AREA = '1 = dentro de comunidade mapeada pelo IBGE; 2 = comunidade não mapeada; 3 = fora de comunidade.'.freeze

  AREA = lambda do |dado|
    classes = Extrair.campos(dado, no_ponto: 'Point', raio_25m: 'Radius25m', raio_100m: 'Radius100m')
    classes.empty? ? nil : classes.merge('legenda' => LEGENDA_DA_AREA)
  end

  CRIMES = lambda do |dado|
    resumo = Extrair.campos(dado, cidade: 'City', uf: 'State', ocorrencias_12_meses: 'TotalLast360DaysOccurrences',
                                  media_por_mes: 'AverageTotalOccurrencesByMonth')
    tipos = Extrair.itens(dado['CriminalOccurrencesByNature'], tipo: 'CriminalNature', ocorrencias_12_meses: 'Last360DaysOccurrences')
    Extrair.sem_vazio(resumo.merge('por_tipo' => tipos))
  end

  VISTORIA = lambda do |dado|
    Extrair.sem_vazio(Extrair.campos(dado, tipo: 'Tipology', uso: 'ResidenceType', area_m2: 'PropertyAreaInM2', comodos: 'TotalRooms',
                                           nota_da_estrutura: 'PropertyStructuralScore', nota_do_acabamento: 'PropertySecondaryScore',
                                           endereco_exato: 'IsExactMatch', bairro: 'Neighborhood', cidade: 'City', uf: 'State'))
  end

  FONTE = Autonomia::FerramentasProntas::Fonte.new(
    chave: 'risco_endereco', slug: 'pronta_risco_endereco', nome: 'Risco do endereço',
    descricao: 'Consulta paga: o risco de um endereço — se fica em área de comunidade, a criminalidade da cidade (só SP, ' \
               'RJ e MG) ou a vistoria do imóvel. O cliente não precisa saber o CEP: mande a cidade, ou a rua, o número e a ' \
               'cidade. Não diz quem mora no endereço.',
    consultas: [
      Premium::ConsultaPaga.new(
        nome: 'area_de_risco', descricao: 'se o endereço fica em área de comunidade. Sem o CEP, mande a rua, o número e a cidade',
        obrigatorios: [Premium::Parametros::NUMERO], opcionais: Premium::Parametros::PELO_ENDERECO, pelo_endereco: true,
        dataset: Premium::Dataset.new(nome: 'address_risk', rota: '/enderecos', resposta: 'AddressRiskData', custo: '0.08',
                                      preco: '0.12', busca: POR_CEP_E_NUMERO, extrair: AREA)
      ),
      Premium::ConsultaPaga.new(
        nome: 'criminalidade', descricao: 'as ocorrências de crime da cidade (SP, RJ e MG). Basta a cidade; o CEP também serve',
        obrigatorios: [], opcionais: [Premium::Parametros::CEP, Premium::Parametros::CIDADE, Premium::Parametros::UF], pelo_endereco: true,
        dataset: Premium::Dataset.new(nome: 'criminal_statistics_data', rota: '/enderecos', resposta: 'CriminalStatisticsData',
                                      custo: '0.06', preco: '0.09', busca: ->(params) { "zipcode{#{params['cep']}}" }, extrair: CRIMES)
      ),
      Premium::ConsultaPaga.new(
        nome: 'vistoria', descricao: 'o tipo, a área e as notas da vistoria do imóvel. Sem o CEP, mande a rua, o número e a cidade',
        obrigatorios: [Premium::Parametros::NUMERO], opcionais: Premium::Parametros::PELO_ENDERECO, pelo_endereco: true,
        dataset: Premium::Dataset.new(nome: 'partner_rede_vistorias_address', rota: '/marketplace', resposta: 'RedeVistoriasData',
                                      custo: '0.26', preco: '0.39', busca: POR_CEP_E_NUMERO, extrair: VISTORIA, prazo: 30,
                                      cobra_sem_registro: false)
      )
    ],
    limite_diario: nil, flag: Premium::FLAG,
    termos: 'BigDataCorp (contrato da plataforma); a vistoria é da parceira Rede Vistorias, pela BigDataCorp.'
  )
end
