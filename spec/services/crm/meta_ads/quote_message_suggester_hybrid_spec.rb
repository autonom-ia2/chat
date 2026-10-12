require 'rails_helper'

# Proposta parada fora das 24h (chat#1349): com o WhatsApp Híbrido pronto a conversa responde pelo WhatsApp API,
# então a IA é chamada em vez de devolver window_closed. Sem ele, nada muda.
RSpec.describe Crm::MetaAds::QuoteMessageSuggester do
  include CrmHybridHelpers

  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true', WHATSAPP_HYBRID_ACCOUNT_IDS: '*' do
      travel_to(Time.zone.parse('2026-10-06T15:00:00-03:00')) { example.run }
    end
  end

  let(:scenario) { build_crm_hybrid_scenario }
  let(:card) { scenario[:card] }
  let(:conversation) { scenario[:conversation] }
  let(:said) { 'Pode me mandar o valor com a instalação inclusa?' }
  let(:credential) { { api_key: 'synthetic-test-key', source: :hook } }
  let(:client) { instance_double(Crm::Ai::ResponsesClient) }
  let(:resolver) { instance_double(Crm::Ai::CredentialResolver, configured?: true, resolve: credential) }
  let(:answer) do
    { 'applies' => true, 'reason' => 'none', 'message' => 'Oi! Consegui o valor com a instalação inclusa. Posso te mandar?',
      'source_quote' => 'o valor com a instalação inclusa', 'includes_outside_contact' => false }
  end

  before do
    conversation.messages.incoming.last.update!(content: said)
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolver)
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
    allow(client).to receive(:create).and_return(text: answer.to_json)
  end

  def suggest
    described_class.new(card: card, conversation: conversation, language: 'pt_BR')
  end

  it 'fora das 24h mas com o Híbrido pronto, não devolve window_closed e chama a IA' do
    expect(Crm::FollowUps::MessagingWindow.new(conversation).requires_template?).to be(true)
    expect(conversation.whatsapp_api_reply?).to be(true)

    expect(suggest.unavailable_reason).to be_nil
    expect(suggest.perform).to include(applies: true, message: answer['message'])
    expect(client).to have_received(:create).once
  end

  it 'fora das 24h sem o Híbrido pronto, devolve window_closed e não chama a IA' do
    scenario[:connection].update!(status: 'disconnected')

    expect(suggest.unavailable_reason).to eq('window_closed')
    expect(suggest.perform).to include(applies: false, reason: 'window_closed')
    expect(client).not_to have_received(:create)
  end

  it 'conta fora do piloto mantém window_closed' do
    with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: '999999') do
      expect(suggest.unavailable_reason).to eq('window_closed')
    end
  end
end
