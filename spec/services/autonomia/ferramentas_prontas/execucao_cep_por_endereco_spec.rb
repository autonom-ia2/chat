require 'rails_helper'

# #2858 — regra "QI 70" no CEP: o cliente diz a rua, não o CEP. A consulta `por_endereco` acha o CEP pela rua e pela
# cidade (ViaCEP), e a UF sai da cidade.
RSpec.describe Autonomia::FerramentasProntas::Execucao do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end
  let(:ferramenta) { incluir_pronta('cep', conta: account, agente: agent) }
  let(:paulista) { 'https://viacep.com.br/ws/SP/Sao%20Paulo/Avenida%20Paulista/json/' }
  let(:da_viacep) do
    [{ cep: '01311-300', logradouro: 'Avenida Paulista', complemento: 'de 1047 a 1865 - lado ímpar', bairro: 'Bela Vista',
       localidade: 'São Paulo', uf: 'SP', ibge: '3550308', ddd: '11' },
     { cep: '01310-100', logradouro: 'Avenida Paulista', complemento: 'de 1 a 609 - lado ímpar', bairro: 'Bela Vista',
       localidade: 'São Paulo', uf: 'SP', ibge: '3550308', ddd: '11' }]
  end

  before do
    resolver_hosts_das_prontas
    ligar_prontas(account)
  end

  def por_endereco(argumentos)
    executar_pronta(ferramenta, { 'consulta' => 'por_endereco' }.merge(argumentos))
  end

  it '"CEP da Avenida Paulista": a rua e a cidade bastam (a UF sai dela); varios CEPs vem com bairro e faixa de numero' do
    fonte_responde(paulista, da_viacep)

    saida = por_endereco('logradouro' => 'Avenida Paulista', 'cidade' => 'São Paulo')

    expect(saida['situacao']).to eq('encontrado')
    expect(saida['dados']).to include('cidade' => 'São Paulo', 'uf' => 'SP', 'total' => 2)
    expect(saida['dados']['ceps'].first).to eq('cep' => '01311-300', 'logradouro' => 'Avenida Paulista',
                                               'complemento' => 'de 1047 a 1865 - lado ímpar', 'bairro' => 'Bela Vista')
  end

  it 'com limite de resultados: ate 10 CEPs, com o total' do
    muitos = Array.new(15) { |indice| da_viacep.first.merge(cep: format('01311-%03d', indice)) }
    fonte_responde(paulista, muitos)

    dados = por_endereco('logradouro' => 'Avenida Paulista', 'cidade' => 'sao paulo', 'uf' => 'sp')['dados']

    expect(dados).to include('total' => 15, 'mostrando' => 10)
    expect(dados['ceps'].size).to eq(10)
  end

  it 'o CEP da rua (faixa de numero) vem antes do CEP especial de um predio ou orgao (sufixo 900 a 999)' do
    predio = da_viacep.first.merge(cep: '01311-921', complemento: '1159')
    fonte_responde(paulista, [predio, *da_viacep])

    ceps = por_endereco('logradouro' => 'Avenida Paulista', 'cidade' => 'São Paulo')['dados']['ceps'].pluck('cep')

    expect(ceps).to eq(%w[01311-300 01310-100 01311-921])
  end

  it 'rua que a fonte nao conhece: "nao encontrado"' do
    fonte_responde(paulista, [])

    expect(por_endereco('logradouro' => 'Avenida Paulista', 'cidade' => 'São Paulo')['situacao']).to eq('nao_encontrado')
  end

  it 'rua curta, sem cidade ou cidade homonima: pedido invalido, sem chamar a fonte' do
    expect(por_endereco('logradouro' => 'Av', 'cidade' => 'São Paulo')['campo']).to eq('logradouro')
    expect(por_endereco('logradouro' => 'Avenida Paulista')['campo']).to eq('cidade')
    expect(por_endereco('logradouro' => 'Rua Um', 'cidade' => 'Bom Jesus')).to include('campo' => 'uf', 'candidatos' => %w[PB PI RN RS SC])
    expect(a_request(:get, /viacep/)).not_to have_been_made
  end

  it 'a consulta pelo CEP continua igual' do
    fonte_responde('https://brasilapi.com.br/api/cep/v2/01001000', { cep: '01001000', state: 'SP', city: 'São Paulo', street: 'Praça da Sé' })

    expect(executar_pronta(ferramenta, 'consulta' => 'endereco', 'cep' => '01001-000')['dados']).to include('cep' => '01001-000')
  end
end
