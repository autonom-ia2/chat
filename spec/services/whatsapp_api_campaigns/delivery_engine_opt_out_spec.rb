require 'rails_helper'

# chat#737: a campanha da API oficial reconfere a recusa do contato antes de CADA mensagem.
# Arquivo separado do delivery_engine_spec (em quarentena por causa do ENV); aqui o Config.enabled? é stubado.
RSpec.describe WhatsappApiCampaigns::DeliveryEngine do
  before do
    allow(WhatsappApiCampaigns::Config).to receive(:enabled?).and_return(true)
  end

  def running_campaign_with(*names_and_phones)
    account, user, inbox, label = create_account_user_inbox_and_label
    contacts = names_and_phones.map do |name, phone|
      create_labelled_contact(account: account, label: label, name: name, phone_number: phone)
    end
    campaign = create_whatsapp_api_campaign(account: account, user: user, inbox: inbox, label: label)
    WhatsappApiCampaigns::AudienceResolver.new(campaign).perform
    campaign.update!(status: :running)
    [account, campaign, contacts]
  end

  it 'não envia ao destinatário pendente de campanha em andamento cujo contato recusou depois' do
    account, campaign, (ana, bia) = running_campaign_with(['Ana Silva', '+5511987654321'], ['Bia Souza', '+5521987654321'])

    described_class.new(campaign).perform
    expect(campaign.whatsapp_api_campaign_recipients.find_by(contact: ana)).to be_sent

    bia.opt_out!(source: 'prospecting')
    described_class.new(campaign).perform

    recipient = campaign.whatsapp_api_campaign_recipients.find_by(contact: bia)
    expect(recipient).to be_cancelled
    expect(recipient.cancelled_at).to be_present
    expect(recipient.last_error_message).to eq('opted_out')
    expect(recipient.message_id).to be_nil
    expect(Message.where(account_id: account.id).count).to eq(1)
  end

  it 'termina como concluída, sem falhas, quando o único pulado é recusado' do
    _account, campaign, (_ana, bia) = running_campaign_with(['Ana Silva', '+5511987654321'], ['Bia Souza', '+5521987654321'])
    bia.opt_out!(source: 'manual')

    3.times { described_class.new(campaign).perform }

    expect(campaign.reload).to be_completed
    expect(campaign.failed_count).to eq(0)
    expect(campaign.sent_count).to eq(1)
    expect(campaign.cancelled_count).to eq(1)
    expect(campaign.opted_out_count).to eq(1)
  end

  it 'reconfere também o destinatário devolvido a pendente depois de envio interrompido' do
    account, campaign, contacts = running_campaign_with(['Ana Silva', '+5511987654321'])
    ana = contacts.first
    recipient = campaign.whatsapp_api_campaign_recipients.find_by(contact: ana)
    recipient.update!(status: :sending, attempts: 1, updated_at: 20.minutes.ago)
    ana.opt_out!(source: 'email_unsubscribe')

    described_class.new(campaign).perform

    expect(recipient.reload).to be_cancelled
    expect(recipient.last_error_message).to eq('opted_out')
    expect(Message.where(account_id: account.id).count).to eq(0)
    expect(campaign.reload).to be_completed
  end

  it 'envia normalmente a quem não recusou' do
    account, campaign, contacts = running_campaign_with(['Ana Silva', '+5511987654321'])

    ana = contacts.first

    described_class.new(campaign).perform

    expect(campaign.whatsapp_api_campaign_recipients.find_by(contact: ana)).to be_sent
    expect(Message.where(account_id: account.id).count).to eq(1)
    expect(campaign.reload).to be_completed
  end
end
