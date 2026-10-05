require 'rails_helper'

RSpec.describe Autonomia::Decisores::Extrator do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) do
    create(:message, conversation: conversation, account: account, inbox: conversation.inbox, message_type: :incoming,
                     content: "Nome: Joana Lima\nTelefone: (11) 98888-7777\nEmpresa: Lima Seguros")
  end
  let(:estado) { Autonomia::Decisores::Estado.new(conversation: conversation, message: message) }
  let(:campos) do
    [{ chave: 'nome', descricao: 'Nome de quem preencheu', destino: 'contato.nome' },
     { chave: 'telefone', descricao: 'Telefone', destino: 'contato.telefone' },
     { chave: 'empresa', descricao: 'Empresa', destino: 'empresa.nome' }]
  end
  let(:decisor) { create(:autonomia_decisor, account: account, campos: campos) }
  let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }

  before do
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k' }))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
  end

  it 'pede ao modelo um campo por chave, pela chave de IA da conta, e devolve só o que veio preenchido' do
    allow(cliente).to receive(:create).and_return(text: { nome: 'Joana Lima', telefone: '+5511988887777', empresa: nil }.to_json)

    expect(described_class.new(decisor: decisor).extrair(estado)).to eq('nome' => 'Joana Lima', 'telefone' => '+5511988887777')
    expect(Crm::Ai::ResponsesClient).to have_received(:new).with(hash_including(feature: 'decisor_extracao', account: account))
    expect(cliente).to have_received(:create) do |**args|
      schema = args[:schema][:schema]
      expect(schema[:required]).to eq(%w[nome telefone empresa])
      # #1000 — o código do país é completado pelo Aplicador, não inventado pelo modelo.
      expect(schema[:properties]['telefone'][:description]).to include('country code only if written')
      expect(JSON.parse(args[:input])['messages'].first).to include('Joana Lima')
    end
  end

  it 'não chama o modelo quando o Decisor não tem campos' do
    sem_campos = create(:autonomia_decisor, account: account)

    expect(described_class.new(decisor: sem_campos).extrair(estado)).to eq({})
    expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
  end

  it 'falha com código quando a conta não tem chave de IA' do
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: nil))

    expect { described_class.new(decisor: decisor).extrair(estado) }.to raise_error(described_class::Error, 'ia_nao_configurada')
  end
end
