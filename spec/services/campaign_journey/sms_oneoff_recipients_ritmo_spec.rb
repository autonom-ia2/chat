require 'rails_helper'

# #3063, item 2: fora do limite por cliente da conta, o destinatário da campanha de SMS espera `queued` com adiado_ate
# (não vira falha no fim da rodada) e sai na retomada; a retomada relê o selo de SMS do público.
RSpec.describe CampaignJourney::SmsOneoffRecipients, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let!(:inbox) { journey_twilio_sms_inbox(account) }
  let(:content) { "Nome,Celular\nAna Souza,11987654321\nCaio Reis,31987654321\n" }
  let!(:audience) { saved_audience(account: account, user: user, content: content, mapping: { 'name' => 0, 'phone' => 1 }) }
  let(:campaign) do
    campaign = create(:campaign, account: account, inbox: inbox, audience: [], title: 'Parcela', message: 'Oi {{contact.first_name}}.')
    CampaignAudienceLink.create!(account: account, campaign: campaign, campaign_import: audience)
    campaign
  end
  let(:ana) { account.contacts.find_by!(name: 'Ana Souza') }

  before do
    account.update_columns(settings: account.settings.to_h.merge('ritmo_de_envio' => { 'limite' => { 'mensagens' => 1, 'dias' => 7 } })) # rubocop:disable Rails/SkipsModelValidations
    Autonomia::EnvioAoCliente.create!(account: account, contact: ana, origem: 'campanha_whatsapp', enviado_em: 1.day.ago)
  end

  def service = Twilio::OneoffSmsCampaignService.new(campaign: campaign)
  def recipient_of(contact) = CampaignRecipient.find_by!(campaign: campaign, contact: contact)

  it 'adia quem chegou ao limite sem marcar falha, manda aos outros e conta o que saiu' do
    sent = stub_twilio_sms

    service.perform

    expect(sent.pluck('To')).to eq(['+5531987654321'])
    adiada = recipient_of(ana)
    expect(adiada).to be_queued
    expect(adiada.adiado_ate).to be_within(1.minute).of(6.days.from_now)
    expect(Autonomia::EnvioAoCliente.where(origem: 'campanha_sms').count).to eq(1)
  end

  it 'manda o adiado na retomada quando a hora chega' do
    sent = stub_twilio_sms
    service.perform
    recipient_of(ana).update!(adiado_ate: 1.minute.ago)
    Autonomia::EnvioAoCliente.where(contact: ana).delete_all

    service.retomar_adiados

    expect(sent.pluck('To')).to contain_exactly('+5531987654321', '+5511987654321')
    expect(recipient_of(ana)).to be_sent
  end

  it 'pula o adiado na retomada quando o selo de SMS do público foi desligado' do
    sent = stub_twilio_sms
    service.perform
    recipient_of(ana).update!(adiado_ate: 1.minute.ago)
    audience.update!(channels: audience.channels.merge('sms' => audience.channels['sms'].merge('enabled' => false)))

    service.retomar_adiados

    expect(sent.size).to eq(1)
    expect(recipient_of(ana)).to be_skipped
    expect(recipient_of(ana).error_message).to eq(described_class::CHANNEL_DISABLED_REASON)
  end
end
