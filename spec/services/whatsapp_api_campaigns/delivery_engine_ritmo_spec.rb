require 'rails_helper'

# #3063, item 2: fora do limite por cliente ou do horário de envio da conta, o destinatário da campanha do WhatsApp API
# espera (pendente, com adiado_ate) e a campanha não termina nem segura a caixa até lá.
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

  def limite_de_uma_por_semana(account)
    account.update_columns(settings: account.settings.to_h.merge('ritmo_de_envio' => { 'limite' => { 'mensagens' => 1, 'dias' => 7 } })) # rubocop:disable Rails/SkipsModelValidations
  end

  it 'adia quem já chegou ao limite, manda aos outros e conta o que saiu' do
    account, campaign, (ana, bia) = running_campaign_with(['Ana Silva', '+5511987654321'], ['Bia Souza', '+5521987654321'])
    limite_de_uma_por_semana(account)
    Autonomia::EnvioAoCliente.create!(account: account, contact: ana, origem: 'campanha_whatsapp', enviado_em: 1.day.ago)

    3.times { described_class.new(campaign).perform }

    adiada = campaign.whatsapp_api_campaign_recipients.find_by(contact: ana)
    expect(adiada).to be_pending
    expect(adiada.adiado_ate).to be_within(1.minute).of(6.days.from_now)
    expect(adiada.attempts).to eq(0)
    expect(campaign.whatsapp_api_campaign_recipients.find_by(contact: bia)).to be_sent
    expect(Autonomia::EnvioAoCliente.where(contact: bia, origem: 'campanha_whatsapp_api').count).to eq(1)
    expect(Message.where(account_id: account.id).count).to eq(1)
    expect(campaign.reload).to be_running
  end

  it 'manda o adiado quando a hora chega e termina a campanha' do
    account, campaign, (ana,) = running_campaign_with(['Ana Silva', '+5511987654321'])
    campaign.whatsapp_api_campaign_recipients.find_by(contact: ana).update!(adiado_ate: 1.minute.ago)

    described_class.new(campaign).perform

    expect(campaign.whatsapp_api_campaign_recipients.find_by(contact: ana)).to be_sent
    expect(Message.where(account_id: account.id).count).to eq(1)
    expect(campaign.reload).to be_completed
  end

  it 'não pega o destinatário antes da hora' do
    account, campaign, (ana,) = running_campaign_with(['Ana Silva', '+5511987654321'])
    campaign.whatsapp_api_campaign_recipients.find_by(contact: ana).update!(adiado_ate: 1.hour.from_now)

    described_class.new(campaign).perform

    expect(Message.where(account_id: account.id).count).to eq(0)
    expect(campaign.reload).to be_running
  end
end
