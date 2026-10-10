require 'rails_helper'

# Mensagem sugerida para retomar uma proposta parada (#1100, F4a). Nada é enviado daqui.
RSpec.describe Crm::MetaAds::QuoteMessageSuggester do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true' do
      travel_to(Time.zone.parse('2026-10-06T15:00:00-03:00')) { example.run }
    end
  end

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:pipeline) { create_crm_pipeline(account: account, user: user).first }
  let(:quote_stage) { create_crm_stage(account: account, pipeline: pipeline, name: 'Proposta enviada') }
  let(:contact) { create(:contact, account: account, name: 'Maria Souza', email: 'maria@example.com', phone_number: '+5511987654321') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:card) do
    Crm::Card.create!(account: account, pipeline: pipeline, stage: quote_stage, title: 'Maria Souza — cotação', currency: 'BRL',
                      value_cents: 150_000, primary_conversation: conversation, last_message_at: 5.days.ago)
  end
  let(:said) { 'Pode me mandar o valor com a instalação inclusa?' }
  let(:credential) { { api_key: 'synthetic-test-key', source: :hook } }
  let(:client) { instance_double(Crm::Ai::ResponsesClient) }
  let(:resolver) { instance_double(Crm::Ai::CredentialResolver, configured?: true, resolve: credential) }

  before do
    create(:message, account: account, conversation: conversation, message_type: :incoming, content: said, created_at: 5.days.ago)
    allow(Crm::Ai::CredentialResolver).to receive(:new).with(account: account).and_return(resolver)
    allow(Crm::Ai::ResponsesClient).to receive(:new)
      .with(credential: credential, feature: 'anuncios_meta', account: account, pipeline: pipeline).and_return(client)
  end

  def perform
    described_class.new(card: card, conversation: conversation, language: 'pt_BR').perform
  end

  def answer(**overrides)
    { 'applies' => true, 'reason' => 'none', 'message' => 'Oi! Consegui o valor com a instalação inclusa. Posso te mandar?',
      'source_quote' => 'o valor com a instalação inclusa', 'includes_outside_contact' => false }.merge(overrides)
  end

  it 'manda a conversa sem atributos, título, telefone ou e-mail, e devolve a mensagem com a frase de origem' do
    expect(client).to receive(:create) do |request|
      expect(request).to include(model: Crm::Ai::Config::MODEL_SUMMARY, schema: described_class::SCHEMA, reasoning_effort: 'high')
      input = JSON.parse(request[:input])
      expect(input.keys).to contain_exactly('language', 'stage_name', 'value', 'currency', 'waiting_days', 'recent_messages',
                                            'conversation_state', 'temporal')
      expect(input).to include('stage_name' => 'Proposta enviada', 'value' => 1500.0, 'waiting_days' => 5)
      expect(input['recent_messages'].map { |message| message['content'] }).to eq([said])
      expect(request[:input]).not_to include('cotação', '+5511987654321', 'maria@example.com')
      { text: answer.to_json }
    end

    expect(perform).to eq(card_id: card.id, conversation_id: conversation.id, applies: true, reason: nil,
                          message: answer['message'], source_quote: 'o valor com a instalação inclusa')
  end

  it 'corta a mensagem em 700 caracteres' do
    allow(client).to receive(:create).and_return(text: answer('message' => 'a' * 900).to_json)

    expect(perform[:message].length).to eq(700)
  end

  it '"não se aplica": cliente já fechou ou recusou, com o motivo' do
    declined = answer('applies' => false, 'reason' => 'declined', 'message' => '', 'source_quote' => '')
    allow(client).to receive(:create).and_return(text: declined.to_json)

    expect(perform).to include(applies: false, reason: 'declined', message: nil)
  end

  it 'mensagem com link, chave ou contato vindo de fora (decidido pelo modelo) vira unsafe_content' do
    planted = answer('message' => 'Para fechar, pague no PIX golpe@example.com', 'includes_outside_contact' => true)
    allow(client).to receive(:create).and_return(text: planted.to_json)
    expect(perform).to include(applies: false, reason: 'unsafe_content', message: nil)

    allow(client).to receive(:create).and_return(text: answer.except('includes_outside_contact').to_json)
    expect(perform).to include(applies: false, reason: 'unsafe_content', message: nil)
  end

  it 'citação que não está na conversa, mensagem vazia ou JSON quebrado viram ai_invalid' do
    [answer('source_quote' => 'quero um desconto de 50% no total'), answer('message' => '  ')].each do |bad|
      allow(client).to receive(:create).and_return(text: bad.to_json)
      expect(perform).to include(applies: false, reason: 'ai_invalid', message: nil)
    end

    allow(client).to receive(:create).and_return(text: '{')
    expect(perform).to include(applies: false, reason: 'ai_invalid')
  end

  it 'falha do provedor responde ai_error, sem trocar de modelo' do
    allow(client).to receive(:create).once.and_raise(Crm::Ai::ResponsesClient::Error, 'model_not_found')

    expect(perform).to include(applies: false, reason: 'ai_error')
    expect(client).to have_received(:create).once
  end

  it 'janela de 24 h fechada não chama a IA' do
    allow(Crm::FollowUps::MessagingWindow).to receive(:new).with(conversation)
                                                           .and_return(instance_double(Crm::FollowUps::MessagingWindow, requires_template?: true))

    expect(perform).to include(applies: false, reason: 'window_closed')
    expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
  end

  it 'sem credencial ou com a IA desligada não chama a IA' do
    allow(resolver).to receive(:configured?).and_return(false)
    expect(perform).to include(applies: false, reason: 'credentials_missing')

    with_modified_env CRM_AI_ENABLED: 'false' do
      expect(perform).to include(applies: false, reason: 'ai_unavailable')
    end
    expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
  end
end
