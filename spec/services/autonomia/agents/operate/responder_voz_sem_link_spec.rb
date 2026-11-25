require 'rails_helper'

# #3211 (P7): link lido em voz não serve ao cliente. Resposta em voz com link sai em texto; sem link segue em áudio.
# A regra vale para toda resposta em voz, não só para quem tem as opções da paridade da conversa.
RSpec.describe Autonomia::Agents::Operate::Responder do
  let(:account) { conta_da_fase2 }
  let(:cloud) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { cloud.inbox }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, source_id: '5511937016094') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact_inbox: contact_inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) { criar_principal(account, config: { 'with_knowledge' => false }) }
  let(:agent_inbox) { Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot) }
  let!(:pergunta) do
    create(:message, account: account, inbox: conversation.inbox, conversation: conversation, message_type: :incoming, content: 'quero pagar')
  end

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false') { example.run }
  end

  before do
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    allow_any_instance_of(described_class).to receive(:voice_reply_applies?).and_return(true) # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(described_class).to receive(:synthesize_audio).and_return('OggS-bytes') # rubocop:disable RSpec/AnyInstance
  end

  def responde(reply)
    resultado = Autonomia::Agents::AnswerResult.new(reply: reply, confidence: 0.9, handoff: { should: false, reason: nil }, interacao: nil)
    allow(Autonomia::Agents::Answerer).to receive(:new) do
      answerer = instance_double(Autonomia::Agents::Answerer)
      allow(answerer).to receive(:answer).and_return(resultado)
      answerer
    end
  end

  def perform
    described_class.new(conversation: conversation, agent_inbox: agent_inbox, reply_to_message_id: pergunta.id).perform
  end

  def enviadas
    conversation.messages.outgoing.order(:id).to_a
  end

  it 'resposta com link sai em texto' do
    responde('Seu link de pagamento: https://pagamento.exemplo.com/?IdCarrinho=123')
    perform

    expect(enviadas.sole.content).to include('https://pagamento.exemplo.com/?IdCarrinho=123')
    expect(enviadas.sole.content_attributes).not_to have_key('autonomia_voice')
  end

  it 'HTTPS maiúsculo também é link' do
    responde('Acesse HTTPS://exemplo.com')
    perform

    expect(enviadas.sole.content_attributes).not_to have_key('autonomia_voice')
  end

  it 'sem link segue em áudio' do
    responde('Seu seguro está pronto.')
    perform

    expect(enviadas.sole.content_attributes['autonomia_voice']).to be(true)
  end
end
