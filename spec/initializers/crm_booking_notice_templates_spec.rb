require 'rails_helper'

# Assinante do `whatsapp_templates.consentimento_ligado` (#1524, contrato do #1603), em
# `config/initializers/crm_booking_notice_templates.rb`.
RSpec.describe 'assinante de whatsapp_templates.consentimento_ligado', type: :job do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:job) { Crm::BookingV2::NoticeTemplateEnsureJob }

  # Ligar o Aviso de serviço é o que autoriza criar: o agendamento reage enfileirando a criação para a conta.
  it 'evento com marca utility: enfileira a criação da conta' do
    expect do
      ActiveSupport::Notifications.instrument('whatsapp_templates.consentimento_ligado', account_id: account.id, marca: 'utility')
    end.to have_enqueued_job(job).with(account.id)
  end

  # Divulgação não autoriza modelo de utilidade: os avisos do agendamento não dependem dela.
  it 'evento com marca marketing: não enfileira' do
    expect do
      ActiveSupport::Notifications.instrument('whatsapp_templates.consentimento_ligado', account_id: account.id, marca: 'marketing')
    end.not_to have_enqueued_job(job)
  end

  # Evento sem conta não tem para quem criar: nada vai para a fila (o job sairia vazio).
  it 'evento sem account_id: não enfileira' do
    expect do
      ActiveSupport::Notifications.instrument('whatsapp_templates.consentimento_ligado', account_id: nil, marca: 'utility')
    end.not_to have_enqueued_job(job)
  end

  # A cadeia real: a linha gravada pela tela de Modelos publica o evento depois do commit e o assinante enfileira.
  it 'ligar o Aviso de serviço pelo registro enfileira' do
    expect do
      WhatsappTemplateConsent.create!(account: account, marca: 'utility', acao: WhatsappTemplateConsent::LIGOU,
                                      versao_aviso: 'v1', texto_aviso: 'Aviso.')
    end.to have_enqueued_job(job).with(account.id)
  end

  # Contrato do #1603: fila fora do ar não derruba quem publica (a autorização já foi gravada); vai ao log e ao tracker.
  it 'erro ao enfileirar: não sobe e vai ao tracker' do
    tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)
    allow(job).to receive(:perform_later).and_raise(StandardError)

    expect do
      ActiveSupport::Notifications.instrument('whatsapp_templates.consentimento_ligado', account_id: account.id, marca: 'utility')
    end.not_to raise_error
    expect(tracker).to have_received(:capture_exception)
  end
end
