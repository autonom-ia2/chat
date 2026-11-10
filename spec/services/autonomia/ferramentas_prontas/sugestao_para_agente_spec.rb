require 'rails_helper'

# #2858 F3 — o cartão "pode ganhar": o modelo da conta (dublado aqui, nada pago) escolhe, pela instrução do agente, as
# prontas que combinam; lista vazia é "nenhuma combina". Uma chamada por agente, em segundo plano, guardada com a
# assinatura do catálogo; "Agora não" não volta. A Lia fica de fora.
RSpec.describe Autonomia::FerramentasProntas::SugestaoParaAgente do
  include FerramentasProntasHelper

  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: "Ana#{'A' * 200}", agent_type: 'sdr', instruction: 'Você cota seguro auto.')
  end
  let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }
  let(:credencial) { { api_key: 'chave-de-teste', source: :system } }
  let(:escolha) { %w[fipe cpf] }

  before do
    ligar_consultas(account)
    account.enable_features!(Autonomia::FerramentasProntas::FLAG_VITRINE, Autonomia::FerramentasProntas::FLAG_CONSTRUTOR)
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: credencial))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
    allow(cliente).to receive(:create).and_return({ text: { ferramentas: escolha }.to_json })
  end

  it 'asks the cheap model of the account once, with the agent as data' do
    expect(described_class.new(agent).call).to eq(%w[fipe cpf])

    expect(Crm::Ai::ResponsesClient).to have_received(:new)
      .with(credential: credencial, feature: 'agente_ferramenta_sugestao', account: account, max_retries: 0)
    expect(cliente).to have_received(:create) do |**kwargs|
      expect(kwargs[:model]).to eq(Crm::Ai::Config::MODEL_CLASSIFY)
      expect(kwargs[:instructions]).not_to include('seguro auto.')
      expect(kwargs[:input].sole[:content]).to include('Você cota seguro auto.', '- fipe: Valor do carro (FIPE).')
      expect(kwargs[:schema][:schema][:properties][:ferramentas][:items][:enum]).to include('fipe', 'bancos')
    end
  end

  it 'sends at most 120 characters of the agent name' do
    described_class.new(agent).call

    expect(cliente).to have_received(:create) do |**kwargs|
      expect(kwargs[:input].sole[:content]).to include("AGENTE: #{agent.name.first(120)} (tipo")
    end
  end

  it 'keeps the choice with the date and the catalog signature' do
    described_class.new(agent).call

    sugestao = agent.reload.config['prontas_sugestao']
    expect(sugestao).to include('chaves' => %w[fipe cpf], 'assinatura' => described_class.assinatura(agent))
    expect(sugestao['em']).to be_present
    expect(described_class.atual?(agent)).to be(true)
  end

  context 'when nothing fits' do
    let(:escolha) { [] }

    it 'keeps an empty list: no card' do
      described_class.new(agent).call
      expect(described_class.para_tela(agent.reload)).to eq([])
      expect(described_class.atual?(agent)).to be(true)
    end
  end

  it 'shows only what the agent does not have yet and what the person did not dismiss' do
    described_class.new(agent).call
    incluir_pronta('fipe', conta: account, agente: agent)
    expect(described_class.para_tela(agent.reload)).to eq(%w[cpf])

    described_class.dispensar!(agent, 'cpf')
    expect(described_class.para_tela(agent.reload)).to eq([])
    expect(agent.config['prontas_dispensadas']).to eq(%w[cpf])
  end

  it 'dismissing keeps the rest of the config and does not repeat' do
    agent.update!(config: { 'canal_pedido' => 'instagram' })
    2.times { described_class.dispensar!(agent, 'cep') }

    expect(agent.reload.config).to include('canal_pedido' => 'instagram', 'prontas_dispensadas' => %w[cep])
  end

  it 'what was removed in the Confira leaves the Construtor choice too, so a reopened draft does not offer it again' do
    agent.update!(config: { 'ferramentas_sugeridas' => %w[fipe cep cpf] })

    described_class.dispensar!(agent, 'cpf')

    expect(agent.reload.config['ferramentas_sugeridas']).to eq(%w[fipe cep])
  end

  it 'becomes stale when the account gets a new source, so it is asked again' do
    account.disable_features!(Autonomia::FerramentasProntas::FLAG_CONSULTAS)
    described_class.new(agent).call
    expect(described_class.atual?(agent.reload)).to be(true)

    account.enable_features!(Autonomia::FerramentasProntas::FLAG_CONSULTAS)
    expect(described_class.atual?(agent.reload)).to be(false)
  end

  it 'becomes stale when what the agent is changes (instruction)' do
    described_class.new(agent).call
    agent.reload.update!(instruction: 'Você vende pão.')

    expect(described_class.atual?(agent)).to be(false)
  end

  it 'a draft without instruction is not asked' do
    agent.update!(instruction: '')

    expect(described_class.new(agent).call).to be_nil
    expect(cliente).not_to have_received(:create)
  end

  it 'the agent created by the Construtor gets its choice as the suggestion, without a new call' do
    agent.update!(config: { 'ferramentas_sugeridas' => %w[fipe inventada] })

    described_class.semear_do_construtor!(agent)

    expect(described_class.atual?(agent.reload)).to be(true)
    expect(described_class.para_tela(agent)).to eq(%w[fipe])
    expect(cliente).not_to have_received(:create)
  end

  it 'a broken stored value does not break the reading' do
    agent.update!(config: { 'prontas_sugestao' => 'texto' })

    expect(described_class.atual?(agent)).to be(false)
    expect(described_class.para_tela(agent)).to eq([])
  end

  it 'never suggests to the quote agent (Lia)' do
    lia = Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'insurance_quote')

    expect(described_class.new(lia).call).to be_nil
    expect(described_class.para_tela(lia)).to eq([])
    expect(cliente).not_to have_received(:create)
  end

  it 'without the Construtor flag, nothing runs' do
    account.disable_features!(Autonomia::FerramentasProntas::FLAG_CONSTRUTOR)

    expect(described_class.new(agent).call).to be_nil
    expect(cliente).not_to have_received(:create)
  end

  it 'without AI in the account, nothing is stored and nothing breaks' do
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: nil))

    expect(described_class.new(agent).call).to be_nil
    expect(agent.reload.config).not_to have_key('prontas_sugestao')
  end

  it 'an AI failure stores nothing' do
    allow(cliente).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error, 'fora')

    expect(described_class.new(agent).call).to be_nil
    expect(agent.reload.config).not_to have_key('prontas_sugestao')
  end

  describe Autonomia::FerramentasProntas::SugestaoJob do
    after { Redis::Alfred.delete("#{described_class::TRAVA}:#{agent.id}") }

    it 'enqueues once while the lock lasts, and not when the stored one is current' do
      expect { 2.times { described_class.enfileirar(agent) } }.to have_enqueued_job(described_class).with(agent.id).exactly(:once)

      described_class.perform_now(agent.id)
      Redis::Alfred.delete("#{described_class::TRAVA}:#{agent.id}")
      expect { described_class.enfileirar(agent.reload) }.not_to have_enqueued_job(described_class)
      expect(cliente).to have_received(:create).once
    end
  end
end
