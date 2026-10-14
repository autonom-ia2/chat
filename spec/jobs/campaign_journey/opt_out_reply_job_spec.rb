require 'rails_helper'

# #1449: o job do pedido de parar na resposta a campanha. Sai do ReplyMarkJob (depois da gravação da mensagem da campanha),
# só quando a resposta se aplica; falha do provedor tenta de novo e, esgotada, não marca; sem chave nenhuma, não marca.
# O log leva só ids e a classe do erro.
RSpec.describe CampaignJourney::OptOutReplyJob do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:client) { instance_double(Crm::Ai::ResponsesClient) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+5511987650011') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_AI_ENABLED' => 'true', 'CAMPAIGN_JOURNEY_ENABLED' => 'true') { example.run }
  end

  before do
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
    Redis::Alfred.scan_each(match: 'campaign_journey:opt_out_reply:*') { |key| Redis::Alfred.delete(key) }
  end

  def with_credential(value)
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: value))
  end

  def campaign_reply(content = 'não quero mais receber')
    conversation.messages.create!(account_id: account.id, inbox_id: inbox.id, message_type: :outgoing, content: 'Promoção da semana',
                                  additional_attributes: { 'campaign_id' => 9 }, created_at: 1.hour.ago)
    conversation.messages.create!(account_id: account.id, inbox_id: inbox.id, message_type: :incoming, content: content, sender: contact)
  end

  it 'o ReplyMarkJob enfileira o job só para a primeira resposta a uma campanha' do
    reply = campaign_reply
    clear_enqueued_jobs

    CampaignJourney::ReplyMarkJob.perform_now(reply.id)
    expect(described_class).to have_been_enqueued.with(reply.id).exactly(:once)

    second = conversation.messages.create!(account_id: account.id, inbox_id: inbox.id, message_type: :incoming, content: 'oi', sender: contact)
    CampaignJourney::ReplyMarkJob.perform_now(second.id)
    expect(described_class).to have_been_enqueued.exactly(:once)
  end

  it 'com a chave da conta ou da plataforma: "sim" marca o contato' do
    with_credential({ api_key: 'k', source: :system })
    allow(client).to receive(:create).and_return(text: { pediu_para_parar: 'sim', motivo: 'pedido_explicito_de_parar' }.to_json)

    described_class.perform_now(campaign_reply.id)

    expect(contact.reload.opt_out_source).to eq('campaign_reply')
  end

  it 'sem chave nenhuma: não marca e loga só ids' do
    with_credential(nil)
    reply = campaign_reply('parem de mandar')
    allow(Rails.logger).to receive(:error)

    described_class.perform_now(reply.id)

    expect(contact.reload).not_to be_opted_out
    expect(Rails.logger).to have_received(:error)
      .with("[campaign_journey][opt_out_reply] message=#{reply.id} decisao=sem_credencial erro=Crm::Ai::OptOutClassifier::Unavailable")
    expect(Rails.logger).not_to have_received(:error).with(a_string_including('parem de mandar'))
  end

  it 'provedor fora: tenta de novo e, esgotado, não marca e loga a falha' do
    with_credential({ api_key: 'k' })
    allow(client).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error, 'fora')
    reply = campaign_reply
    allow(Rails.logger).to receive(:error)

    perform_enqueued_jobs { described_class.perform_later(reply.id) }

    expect(client).to have_received(:create).exactly(3).times
    expect(contact.reload).not_to be_opted_out
    expect(Rails.logger).to have_received(:error)
      .with("[campaign_journey][opt_out_reply] message=#{reply.id} decisao=falhou erro=Crm::Ai::ResponsesClient::Error")
    expect(Redis::Alfred.get(CampaignJourney::OptOutReply.counter_key(account.id)).to_i).to eq(1)
  end
end
