require 'rails_helper'

# Casca do antigo "Criar os modelos na Meta" (v1, #1272), retirado em #1612: o job que ainda estiver na fila do Sidekiq
# no deploy roda sem erro, só registra e sai. Não fala com a Meta (o WebMock barra qualquer chamada) nem mexe na página
# ou na caixa.
RSpec.describe Crm::BookingV2::NoticeTemplatesJob do
  include ActiveJob::TestHelper

  let(:account) { create(:account, locale: 'pt_BR') }
  let(:page) { create_booking_profile(account: account, host: create(:user, account: account, role: :administrator)) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }

  it 'com os argumentos de antes, só registra e sai: sem Meta e sem mudar página nem caixa' do
    templates = [{ 'name' => 'lembrete', 'language' => 'pt_BR', 'status' => 'APPROVED' }]
    channel.update_columns(message_templates: templates) # rubocop:disable Rails/SkipsModelValidations
    metadata = page.reload.metadata
    allow(Rails.logger).to receive(:info)
    allow(HTTParty).to receive(:post)
    allow(HTTParty).to receive(:get)

    expect { perform_enqueued_jobs { described_class.perform_later(page.id, channel.inbox.id, %w[booked day_before]) } }.not_to raise_error

    expect(Rails.logger).to have_received(:info).with(include('retired_job_skipped'))
    expect(HTTParty).not_to have_received(:post)
    expect(HTTParty).not_to have_received(:get)
    expect(page.reload.metadata).to eq(metadata)
    expect(channel.reload.message_templates).to eq(templates)
  end

  it 'com página e caixa que não existem mais também não falha' do
    expect { described_class.perform_now(0, 0, %w[booked]) }.not_to raise_error
  end
end
