require 'rails_helper'

RSpec.describe Autonomia::Agents::Specialists::Runner do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(
      account: account, name: 'Bot', agent_type: 'custom', status: :active,
      enabled: true, instruction: 'Atenda.'
    )
  end
  let(:specialist) do
    Autonomia::Agents::Specialist.create!(
      agent: agent, name: 'Especialista de Automóvel', slug: 'auto',
      description: 'cotação de automóvel', instruction: 'Você cota automóvel.'
    )
  end

  def stub_model(text:, credential: 'ai-credential')
    resolver = instance_double(Crm::Ai::CredentialResolver, resolve: credential)
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolver)
    client = instance_double(Crm::Ai::ResponsesClient, create_with_tool_executor: { text: text })
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
    client
  end

  it 'returns prose for the main agent to paraphrase, never structure' do
    # Arrange
    stub_model(text: { resposta: 'Melhor opção: Porto, R$ 1.200.', dados_faltando: [] }.to_json)

    # Act
    result = described_class.new(specialist: specialist, request: 'cotar auto').call

    # Assert
    expect(result).to eq('Melhor opção: Porto, R$ 1.200.')
  end

  it 'appends what is still missing so the main agent knows what to ask' do
    stub_model(text: { resposta: 'Consegui parte.', dados_faltando: ['CEP de pernoite', 'condutor'] }.to_json)

    expect(described_class.new(specialist: specialist, request: 'cotar').call)
      .to eq('Consegui parte. Ainda falta: CEP de pernoite, condutor.')
  end

  it 'runs the specialist with its OWN instruction and its OWN tools' do
    # Arrange
    Autonomia::Agents::Tool.create!(
      account: account, agent: agent, name: 'Cotar', slug: 'cotar_auto',
      endpoint_url: 'https://adapters.example.com/quote', param_schema: []
    )
    specialist.update!(custom_instruction: 'Fale como a Corretora X.', tool_slugs: ['cotar_auto'])
    client = stub_model(text: { resposta: 'ok', dados_faltando: [] }.to_json)

    # Act
    described_class.new(specialist: specialist, request: 'cotar').call

    # Assert
    expect(client).to have_received(:create_with_tool_executor) do |**kwargs|
      expect(kwargs[:instructions]).to eq("Você cota automóvel.\n\nFale como a Corretora X.")
      expect(kwargs[:tools].map { |tool| tool[:name] }).to eq(['cotar_auto'])
    end
  end

  it 'offers no tools when the specialist reserved none' do
    client = stub_model(text: { resposta: 'ok', dados_faltando: [] }.to_json)

    described_class.new(specialist: specialist, request: 'cotar').call

    expect(client).to have_received(:create_with_tool_executor) { |**kwargs| expect(kwargs[:tools]).to be_nil }
  end

  describe 'never raises — a failing specialist must not silence the turn' do
    it 'handles a missing AI credential' do
      stub_model(text: '{}', credential: nil)
      expect(described_class.new(specialist: specialist, request: 'cotar').call)
        .to eq('Especialista indisponível no momento.')
    end

    it 'handles a client error' do
      resolver = instance_double(Crm::Ai::CredentialResolver, resolve: 'cred')
      allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolver)
      client = instance_double(Crm::Ai::ResponsesClient)
      allow(client).to receive(:create_with_tool_executor).and_raise(Crm::Ai::ResponsesClient::Error, 'boom')
      allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)

      expect(described_class.new(specialist: specialist, request: 'cotar').call)
        .to eq('Especialista indisponível no momento.')
    end

    it 'handles invalid JSON from the model' do
      stub_model(text: '<html>manutencao</html>')
      expect(described_class.new(specialist: specialist, request: 'cotar').call)
        .to eq('Especialista indisponível no momento.')
    end

    it 'handles an unexpected error without echoing its message' do
      resolver = instance_double(Crm::Ai::CredentialResolver, resolve: 'cred')
      allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolver)
      client = instance_double(Crm::Ai::ResponsesClient)
      allow(client).to receive(:create_with_tool_executor).and_raise(RuntimeError, 'senha=segredo')
      allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)

      result = described_class.new(specialist: specialist, request: 'cotar').call

      expect(result).to eq('Especialista indisponível no momento.')
      expect(result).not_to include('segredo')
    end

    it 'refuses an empty request without calling the model at all' do
      expect(Crm::Ai::ResponsesClient).not_to receive(:new)
      expect(described_class.new(specialist: specialist, request: '  ').call)
        .to eq('O especialista não recebeu um pedido.')
    end

    it 'handles a model answer that is empty on both fields' do
      stub_model(text: { resposta: '  ', dados_faltando: [] }.to_json)
      expect(described_class.new(specialist: specialist, request: 'cotar').call)
        .to eq('O especialista não conseguiu concluir.')
    end
  end
end
