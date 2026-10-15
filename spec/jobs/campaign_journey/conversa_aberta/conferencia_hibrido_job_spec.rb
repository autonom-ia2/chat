require 'rails_helper'

# #1453: o envio do Híbrido ficou `throttled` (ele tenta de novo em 15 s). A conferência relê a Message do banco até sair
# do `throttled`, com teto de tentativas, e só pede o modelo se o resultado final for `failed`.
RSpec.describe CampaignJourney::ConversaAberta::ConferenciaHibridoJob, :aggregate_failures do
  let(:account) { create(:account) }
  let(:channel) { journey_cloud_channel(account) }
  let(:inbox) { channel.inbox }
  let(:campaign) { create(:campaign, account: account, inbox: inbox, audience: [], template_params: journey_template_params) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                     content_attributes: { 'whatsapp_transport_fallback' => true, 'whatsapp_transport_outcome' => 'throttled' })
  end
  let!(:delivery) do
    CampaignFreeTextDelivery.create!(account: account, campaign: campaign, campaign_recipient_id: 1, inbox_id: inbox.id,
                                     source_id: 'wamid.1453', message_id: message.id)
  end

  def resultado!(outcome)
    message.update!(content_attributes: message.content_attributes.to_h.merge('whatsapp_transport_outcome' => outcome))
  end

  it 'virou failed: pede o modelo' do
    resultado!('failed')

    expect { described_class.perform_now(delivery.id, 1) }
      .to have_enqueued_job(CampaignJourney::ConversaAberta::QuedaJob).with(delivery.id)
  end

  it 'virou failed numa entrega que já caiu para o modelo: não pede de novo' do
    resultado!('failed')
    delivery.update!(fell_back_at: Time.current)

    expect { described_class.perform_now(delivery.id, 1) }.not_to have_enqueued_job
  end

  %w[accepted uncertain].each do |outcome|
    it "virou #{outcome}: encerra sem modelo e registra o motivo" do
      resultado!(outcome)
      allow(Rails.logger).to receive(:info)

      expect { described_class.perform_now(delivery.id, 1) }.not_to have_enqueued_job

      expect(Rails.logger).to have_received(:info).with(include("delivery=#{delivery.id}", "outcome=#{outcome}"))
    end
  end

  it 'ainda throttled antes do teto: confere de novo, com espera maior' do
    freeze_time do
      expect { described_class.perform_now(delivery.id, 1) }
        .to have_enqueued_job(described_class).with(delivery.id, 2).at((described_class::ESPERA * 2).from_now)
    end
  end

  it 'ainda throttled no teto: desiste sem modelo e registra o motivo' do
    allow(Rails.logger).to receive(:warn)

    expect { described_class.perform_now(delivery.id, described_class::TENTATIVAS) }.not_to have_enqueued_job

    expect(Rails.logger).to have_received(:warn).with(include("delivery=#{delivery.id}", 'outcome=throttled'))
  end

  it 'entrega apagada: não faz nada' do
    expect { described_class.perform_now(0, 1) }.not_to have_enqueued_job
  end
end
