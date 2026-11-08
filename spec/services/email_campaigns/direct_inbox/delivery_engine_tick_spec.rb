require 'rails_helper'

# O envio pela caixa manda 1 e-mail por tick e agenda o próximo para 60 a 120 s depois (o ritmo humano). Pausar e
# retomar antes do tick agendado chegar não pode abrir uma segunda cadeia: com duas, a caixa manda no dobro do ritmo.
RSpec.describe EmailCampaigns::DirectInbox::DeliveryEngine, '#tick', :aggregate_failures do
  include ActiveJob::TestHelper

  around do |example|
    with_modified_env(EMAIL_CAMPAIGN_HYGIENE_MODE: 'shadow', EMAIL_REPUTATION_MODE: 'shadow',
                      EMAIL_REPUTATION_PROVIDER_MONITOR: 'false', EMAIL_REPUTATION_PROVIDER_BLOCK: 'false',
                      EMAIL_REPUTATION_AWS_ACCOUNT_ID: '') do
      travel_to(Time.zone.parse('2026-10-05 10:00 -03:00')) { example.run } # segunda-feira, horário comercial
    end
  end

  let(:account) { create(:account) }
  let(:inbox) { create(:channel_email, account: account, email: 'vendas@empresa.com.br').inbox }
  let(:campaign) do
    create(:email_campaign, account: account, delivery_mode: :direct_inbox, sender_inbox: inbox, sender_identity: nil,
                            status: :sending, subject: 'Oi', body_html: '<p>Oi</p>')
  end
  let(:direct_sender) { instance_double(EmailCampaigns::DirectInbox::Sender, deliver: 'direct-1') }

  before do
    allow(EmailCampaigns::Config).to receive(:enabled?).and_return(true)
    allow(EmailCampaigns::DirectInbox::Sender).to receive(:new).and_return(direct_sender)
    %w[ana bia caio dani].each { |nome| create(:email_campaign_recipient, email_campaign: campaign, email: "#{nome}@x.com.br") }
  end

  after { Redis::Alfred.delete(described_class.chain_key(campaign.id)) }

  def ticks_agendados
    enqueued_jobs.count { |job| job[:job] == EmailCampaigns::DirectInbox::TickJob && job[:at] }
  end

  def rodar_o_que_esta_na_fila_agora
    while (job = enqueued_jobs.find { |item| item[:at].nil? })
      enqueued_jobs.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
  end

  def rodar_os_ticks_agendados
    agendados = enqueued_jobs.select { |job| job[:job] == EmailCampaigns::DirectInbox::TickJob && job[:at] }
    enqueued_jobs.replace(enqueued_jobs - agendados)
    agendados.each do |job|
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
      rodar_o_que_esta_na_fila_agora
    end
  end

  it 'pausar e retomar antes do próximo tick segue com uma cadeia, no ritmo de 1 e-mail por tick' do
    described_class.new(campaign).tick
    expect(direct_sender).to have_received(:deliver).once
    expect(ticks_agendados).to eq(1)

    # Retomar manda na hora, como hoje, e a cadeia nova vira a única válida.
    campaign.pause!
    campaign.resume!
    rodar_o_que_esta_na_fila_agora
    expect(direct_sender).to have_received(:deliver).twice

    # O tick da cadeia de antes chega e para sem enviar; só o da cadeia nova manda e agenda o próximo.
    rodar_os_ticks_agendados
    expect(direct_sender).to have_received(:deliver).exactly(3).times
    expect(ticks_agendados).to eq(1)
  end

  it 'tick agendado que chega depois da chave expirar (fila atrasada) segue a cadeia' do
    described_class.new(campaign).tick
    Redis::Alfred.delete(described_class.chain_key(campaign.id))

    rodar_os_ticks_agendados

    expect(direct_sender).to have_received(:deliver).twice
    expect(ticks_agendados).to eq(1)
  end
end
