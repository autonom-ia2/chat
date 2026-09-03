require 'rails_helper'

# #284 (2b) — extração de FAQ com a chamada de LLM stubada: formato, vazio, erro do provedor, dedupe.
RSpec.describe Autonomia::Agents::Faq::Extractor do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:human) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, status: :resolved) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.', config: { 'with_knowledge' => false })
  end
  let(:client) { instance_double(Crm::Ai::ResponsesClient) }

  before do
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: 'cred'))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
  end

  def human_reply(content)
    create(:message, account: account, conversation: conversation, message_type: :outgoing, sender: human, content: content)
  end

  def stub_llm(faqs)
    allow(client).to receive(:create).and_return({ text: { faqs: faqs }.to_json })
  end

  it 'creates pending suggestions from the structured LLM answer, keeping only human source ids' do
    create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact, content: 'Qual o prazo?')
    reply = human_reply('O prazo é de 5 dias úteis.')
    stub_llm([{ question: 'Qual o prazo de entrega?', answer: 'Até 5 dias úteis.', source_message_ids: [reply.id, 999_999] }])

    created = described_class.new(agent: agent, conversation: conversation).call

    expect(created.size).to eq(1)
    expect(created.first).to have_attributes(question: 'Qual o prazo de entrega?', answer: 'Até 5 dias úteis.',
                                             status: 'pending', conversation_id: conversation.id,
                                             source_message_ids: [reply.id])
    expect(client).to have_received(:create).with(hash_including(model: Autonomia::Agents::Config::FAQ_MODEL,
                                                                 schema: described_class::FAQ_SCHEMA))
  end

  it 'does not call the LLM when no human replied' do
    create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact, content: 'Oi')
    expect(client).not_to receive(:create)

    expect(described_class.new(agent: agent, conversation: conversation).call).to eq([])
  end

  it 'returns nothing for an empty faqs list' do
    human_reply('Vou verificar e retorno.')
    stub_llm([])

    expect(described_class.new(agent: agent, conversation: conversation).call).to eq([])
    expect(Autonomia::Agents::FaqSuggestion.count).to eq(0)
  end

  it 'swallows provider errors and malformed JSON' do
    human_reply('Resposta.')
    allow(client).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error, 'boom')
    expect(described_class.new(agent: agent, conversation: conversation).call).to eq([])

    allow(client).to receive(:create).and_return({ text: 'not json' })
    expect(described_class.new(agent: agent, conversation: conversation).call).to eq([])
  end

  it 'dedupes against suggestions already seen (any status) by normalized question' do
    human_reply('Resposta.')
    agent.faq_suggestions.create!(account: account, question: 'Qual é o prazo de entrega?', answer: 'x', status: :ignored)
    stub_llm([{ question: 'qual e o prazo de entrega', answer: 'Até 5 dias.', source_message_ids: [] }])

    expect(described_class.new(agent: agent, conversation: conversation).call).to eq([])
  end

  it 'dedupes against knowledge the agent already has (strong retrieval match)' do
    agent.update!(config: {})
    human_reply('Resposta.')
    hit = Struct.new(:neighbor_distance).new(0.2) # o Retriever devolve entries com o alias SQL neighbor_distance
    allow(Autonomia::Agents::Retriever).to receive(:new).and_return(instance_double(Autonomia::Agents::Retriever, retrieve: [hit]))
    stub_llm([{ question: 'Qual o prazo?', answer: 'Até 5 dias.', source_message_ids: [] }])

    expect(described_class.new(agent: agent, conversation: conversation).call).to eq([])
  end
end
