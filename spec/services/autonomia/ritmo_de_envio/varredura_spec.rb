require 'rails_helper'

# #3063, item 2: a varredura devolve ao envio os destinatários cujo adiamento venceu e apaga o contador velho.
RSpec.describe Autonomia::RitmoDeEnvio::Varredura do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:agora) { Time.current }

  it 'retoma a campanha de WhatsApp Oficial e SMS com destinatário adiado que já pode sair' do
    inbox = create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox
    vencida = create(:campaign, account: account, inbox: inbox, campaign_type: :one_off)
    futura = create(:campaign, account: account, inbox: inbox, campaign_type: :one_off)
    CampaignRecipient.create!(account: account, campaign: vencida, contact: contact, inbox: inbox, status: :queued, adiado_ate: 1.minute.ago)
    CampaignRecipient.create!(account: account, campaign: futura, contact: contact, inbox: inbox, status: :queued, adiado_ate: 1.hour.from_now)

    expect { described_class.rodar(agora: agora) }
      .to have_enqueued_job(CampaignJourney::RetomarAdiadosJob).with(vencida.id).exactly(:once)
    expect(CampaignJourney::RetomarAdiadosJob).not_to have_been_enqueued.with(futura.id)
  end

  it 'apaga do contador o que já não entra em período nenhum' do
    velho = Autonomia::EnvioAoCliente.create!(account: account, contact: contact, origem: 'campanha_email', enviado_em: 40.days.ago)
    recente = Autonomia::EnvioAoCliente.create!(account: account, contact: contact, origem: 'campanha_email', enviado_em: 29.days.ago)

    described_class.rodar(agora: agora)

    expect(Autonomia::EnvioAoCliente.exists?(velho.id)).to be(false)
    expect(Autonomia::EnvioAoCliente.exists?(recente.id)).to be(true)
  end
end
