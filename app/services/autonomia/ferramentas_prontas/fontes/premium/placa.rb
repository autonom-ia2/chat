# HISTÓRICO DA PLACA (#2858, F7, Premium): marca, modelo, ano, restrições e quantos donos o carro já teve, pela placa
# (`/veiculos`, `license_plates`). O nome do dono fica de fora, por desenho. A base da BigDataCorp vai até julho de
# 2021 (documentação dela): carro emplacado depois pode voltar sem registro.
module Autonomia::FerramentasProntas::Fontes::Premium::Placa
  Premium = Autonomia::FerramentasProntas::Premium
  Extrair = Premium::Extrair

  HISTORICO = lambda do |dado|
    veiculo = Extrair.campos(Array(dado['VehicleInfo']).find { |item| item.is_a?(Hash) },
                             marca: 'Brand', modelo: 'Model', versao: 'Version', ano_de_fabricacao: 'FabricationYear',
                             ano_do_modelo: 'ModelYear', combustivel: 'Fuel', tipo: 'Type')
    resumo = Extrair.campos(dado, donos_ao_longo_da_vida: 'TotalOwnersInLifetime', restricao_hoje: 'CurrentlyHasRestrictions',
                                  ja_teve_restricao: 'PreviouslyHadRestrictions', alertas: 'TotalAlerts')
    historico = Extrair.itens(dado['VehicleHistory'], cor: 'Color', categoria: 'Category', cidade: 'Location', uf: 'State')
    Extrair.sem_vazio(veiculo.merge(resumo).merge('historico' => historico))
  end

  FONTE = Autonomia::FerramentasProntas::Fonte.new(
    chave: 'historico_placa', slug: 'pronta_historico_placa', nome: 'Histórico da placa',
    descricao: 'Consulta paga: pela placa, a marca, o modelo, o ano, se tem restrição e quantos donos o veículo já ' \
               'teve. Não traz o nome do dono. A base vai até 2021: carro mais novo pode não ter registro.',
    consultas: [
      Premium::ConsultaPaga.new(
        nome: 'placa', descricao: 'o histórico do veículo', obrigatorios: [Premium::Parametros::PLACA],
        dataset: Premium::Dataset.new(nome: 'license_plates', rota: '/veiculos', resposta: 'LicensePlateData', custo: '0.06',
                                      preco: '0.09', busca: ->(params) { "licenseplate{#{params['placa']}}" }, extrair: HISTORICO)
      )
    ],
    limite_diario: nil, flag: Premium::FLAG,
    termos: 'BigDataCorp (contrato da plataforma). Base histórica até 07/2021.'
  )
end
