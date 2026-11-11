require 'rails_helper'

# #2858 — regra "QI 70" na FIPE: o turno real (não só o Experimente) aceita o NOME da marca e do modelo. O código sai
# das listas da própria fonte (com cache), e o agente nunca pergunta ao leigo um código.
RSpec.describe Autonomia::FerramentasProntas::Execucao do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end
  let(:ferramenta) { incluir_pronta('fipe', conta: account, agente: agent) }
  let(:marcas) { 'https://brasilapi.com.br/api/fipe/marcas/v1/carros' }
  let(:modelos_vw) { 'https://parallelum.com.br/fipe/api/v2/cars/brands/59/models' }
  let(:lista_vw) do
    [{ code: '1', name: 'Gol 1.0 Mi Total Flex 8V 4p' }, { code: '2', name: 'Gol 1.6 Power' }, { code: '3', name: 'Golf 2.0' },
     { code: '4', name: 'Voyage 1.6 MSI Flex 8V 4p' }]
  end
  let(:preco_voyage) do
    { price: 'R$ 58.000,00', brand: 'VW - VolksWagen', model: 'Voyage 1.6 MSI Flex 8V 4p', modelYear: 2020, fuel: 'Flex',
      codeFipe: '005340-6', referenceMonth: 'novembro de 2026' }
  end

  before do
    resolver_hosts_das_prontas
    ligar_prontas(account)
    fonte_responde(marcas, [{ nome: 'GM - Chevrolet', valor: '23' }, { nome: 'VW - VolksWagen', valor: '59' }])
    fonte_responde(modelos_vw, lista_vw)
  end

  def preco(argumentos)
    executar_pronta(ferramenta, { 'consulta' => 'preco', 'tipo' => 'carros' }.merge(argumentos))
  end

  it '"Quanto vale um Voyage 2020?": marca e modelo pelo nome, sem codigo, ate o preco' do
    fonte_responde("#{modelos_vw}/4/years", [{ code: '2020-1', name: '2020 Gasolina' }])
    fonte_responde("#{modelos_vw}/4/years/2020-1", preco_voyage)

    saida = preco('marca' => 'Volkswagen', 'modelo' => 'voyage', 'ano' => 2020)

    expect(saida['situacao']).to eq('encontrado')
    expect(saida['dados']['precos'].first).to include('valor' => 'R$ 58.000,00', 'modelo' => 'Voyage 1.6 MSI Flex 8V 4p')
  end

  it '"Quanto vale um Gol 2020?": varias versoes viram candidatos com codigo, para escolher ou mostrar a faixa' do
    saida = preco('marca' => 'VW', 'modelo' => 'Gol', 'ano' => 2020)

    expect(saida).to include('situacao' => 'pedido_invalido', 'campo' => 'modelo')
    expect(saida['candidatos']).to eq([{ 'codigo' => '1', 'nome' => 'Gol 1.0 Mi Total Flex 8V 4p' }, { 'codigo' => '2', 'nome' => 'Gol 1.6 Power' }])
    expect(saida['orientacao']).to include('2 versões', 'codigo', 'faixa')
    expect(saida['orientacao']).not_to include('Confira com o cliente')
  end

  it 'o nome igual ao da lista escolhe direto, mesmo com outros que comecam igual' do
    fonte_responde("#{modelos_vw}/2/years", [{ code: '2020-1', name: '2020 Gasolina' }])
    fonte_responde("#{modelos_vw}/2/years/2020-1", preco_voyage.merge(model: 'Gol 1.6 Power'))

    expect(preco('marca' => 'volkswagen', 'modelo' => 'GOL 1.6 power', 'ano' => 2020)['situacao']).to eq('encontrado')
  end

  it 'modelos tambem aceita a marca pelo nome' do
    saida = executar_pronta(ferramenta, 'consulta' => 'modelos', 'tipo' => 'carros', 'marca' => 'Volkswagen', 'busca' => 'voyage')

    expect(saida['dados']['modelos']).to eq([{ 'codigo' => '4', 'nome' => 'Voyage 1.6 MSI Flex 8V 4p' }])
  end

  it 'as listas vem do cache: o segundo carro da marca nao baixa marcas nem modelos de novo' do
    cache_em_memoria
    fonte_responde("#{modelos_vw}/3/years", [])

    preco('marca' => 'Volkswagen', 'modelo' => 'Gol', 'ano' => 2020)
    preco('marca' => 'Volkswagen', 'modelo' => 'Golf', 'ano' => 2020)

    expect(a_request(:get, marcas)).to have_been_made.once
    expect(a_request(:get, modelos_vw)).to have_been_made.once
  end

  it 'marca que nao existe: o campo e marca, com o que fazer, nunca codigo_fipe' do
    saida = preco('marca' => 'Gurgel Motors Ltda', 'modelo' => 'X', 'ano' => 2020)

    expect(saida).to include('situacao' => 'pedido_invalido', 'campo' => 'marca')
    expect(saida['orientacao']).to include('Gol é Volkswagen')
  end

  it 'modelo que nao existe na marca: o campo e modelo' do
    expect(preco('marca' => 'Volkswagen', 'modelo' => 'Fusca', 'ano' => 2020)).to include('situacao' => 'pedido_invalido', 'campo' => 'modelo')
  end

  it 'sem marca, modelo nem codigo: o campo e marca, nunca codigo_fipe' do
    expect(preco('ano' => 2020)).to include('situacao' => 'pedido_invalido', 'campo' => 'marca')
    expect(preco('marca' => 'Volkswagen', 'ano' => 2020)).to include('situacao' => 'pedido_invalido', 'campo' => 'modelo')
  end

  it 'sem o ano: a faixa (o ano mais antigo e o mais novo) e os anos que existem, para so entao perguntar' do
    fonte_responde("#{modelos_vw}/4/years", [{ code: '32000-1', name: 'Zero KM Gasolina' }, { code: '2021-1', name: '2021 Gasolina' },
                                             { code: '2020-1', name: '2020 Gasolina' }])
    fonte_responde("#{modelos_vw}/4/years/32000-1", preco_voyage.merge(price: 'R$ 90.000,00', modelYear: 32_000))
    fonte_responde("#{modelos_vw}/4/years/2020-1", preco_voyage)

    dados = preco('marca' => 'Volkswagen', 'modelo' => 'Voyage')['dados']

    expect(dados['anos_disponiveis']).to eq(['Zero KM Gasolina', '2021 Gasolina', '2020 Gasolina'])
    expect(dados['precos'].pluck('valor')).to eq(['R$ 58.000,00', 'R$ 90.000,00'])
    expect(dados['observacao']).to include('faixa', 'ano')
    expect(a_request(:get, "#{modelos_vw}/4/years/2021-1")).not_to have_been_made
  end

  it 'com as listas fora, diz que nao conseguiu consultar' do
    fonte_fora(marcas)
    fonte_fora('https://parallelum.com.br/fipe/api/v2/cars/brands')

    expect(preco('marca' => 'Volkswagen', 'modelo' => 'Gol', 'ano' => 2020)['situacao']).to eq('nao_consegui_consultar')
  end
end
