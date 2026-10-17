require 'rails_helper'

# #1760: cópia encaminhada de outra conversa (#1702) traz texto de outra pessoa. Sem a marca, a IA do CRM
# lia como fala deste cliente e tirava conclusões sobre ele.
RSpec.describe Crm::Ai::ContextBuilder do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline) { create_crm_pipeline(account: account, user: admin).first }
  let(:inbox) { create_crm_inbox(account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }
  let(:card) do
    account.crm_cards.create!(pipeline: pipeline, stage: pipeline.stages.first, title: 'Lead', contact: contact,
                              primary_conversation: conversation, currency: 'BRL')
  end

  def add_message(content:, type:, sender:, attributes: {})
    create(:message, account: account, inbox: inbox, conversation: conversation, content: content,
                     message_type: type, sender: sender, content_attributes: attributes)
  end

  it 'marks a forwarded copy and leaves a normal message untouched' do
    add_message(content: 'quero cotar o seguro do caminhão', type: :incoming, sender: contact)
    add_message(content: 'tenho 3 carretas e pago 900 por mês', type: :outgoing, sender: admin,
                attributes: { 'forwarded' => true, 'forwarded_from' => { 'conversation_id' => 7, 'message_id' => 99 } })

    normal, forwarded = described_class.new(card: card).perform[:recent_messages]

    expect(forwarded[:forwarded]).to be(true)
    expect(forwarded[:content]).to eq("#{described_class::FORWARDED_PREFIX}tenho 3 carretas e pago 900 por mês")
    expect(forwarded[:role]).to eq('human_agent')
    expect(normal).not_to have_key(:forwarded)
    expect(normal[:content]).to eq('quero cotar o seguro do caminhão')
  end

  it 'explains the marker to the classifier, the summary, the follow-up and the quote suggester', :aggregate_failures do
    expect(described_class::FORWARDED_LEGEND).to include('"forwarded": true', described_class::FORWARDED_PREFIX.strip)
    expect(Crm::Ai::ClassifierPrompt::TEXT).to include(described_class::FORWARDED_LEGEND)
    expect(Crm::Ai::ClassifierPrompt::TEXT_COM_AGENTES_IA).to include(described_class::FORWARDED_LEGEND)
    expect(Crm::Ai::ConversationSummarizer.new(card: card).send(:instructions)).to include(described_class::FORWARDED_LEGEND)
    expect(Crm::Ai::FollowUpComposer.new(card: nil, client: nil, context: {}).send(:instructions))
      .to include(described_class::FORWARDED_LEGEND)
  end
end
