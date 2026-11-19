require 'rails_helper'

# Assinante do `whatsapp_templates.consentimento_ligado` (#1524 e #3055, contrato do #1603), em
# `config/initializers/whatsapp_templates_consentimento_ligado.rb`: o Agendamento e a cotação da renovação.
RSpec.describe 'assinante de whatsapp_templates.consentimento_ligado', type: :job do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:job) { Crm::BookingV2::NoticeTemplateEnsureJob }
  let(:job_da_carteira) { Carteira::Cotacao::ModelosJob }

  # Ligar o Aviso de serviço é o que autoriza criar: o agendamento reage enfileirando a criação para a conta.
  it 'evento com marca utility: enfileira a criação da conta' do
    expect do
      ActiveSupport::Notifications.instrument('whatsapp_templates.consentimento_ligado', account_id: account.id, marca: 'utility')
    end.to have_enqueued_job(job).with(account.id)
  end

  # Os 2 modelos da cotação da renovação também são de utilidade: a carteira reage ao mesmo evento (o job reconfere se
  # a cotação está aberta e qual é a caixa).
  it 'evento com marca utility: enfileira também os modelos da cotação da renovação' do
    expect do
      ActiveSupport::Notifications.instrument('whatsapp_templates.consentimento_ligado', account_id: account.id, marca: 'utility')
    end.to have_enqueued_job(job_da_carteira).with(account.id)
  end

  # Divulgação não autoriza modelo de utilidade: os avisos do agendamento não dependem dela.
  it 'evento com marca marketing: não enfileira' do
    expect do
      ActiveSupport::Notifications.instrument('whatsapp_templates.consentimento_ligado', account_id: account.id, marca: 'marketing')
    end.not_to have_enqueued_job(job)
    expect do
      ActiveSupport::Notifications.instrument('whatsapp_templates.consentimento_ligado', account_id: account.id, marca: 'marketing')
    end.not_to have_enqueued_job(job_da_carteira)
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

  # A fila que falha para um job não pode deixar o outro sem o pedido: cada um é enfileirado por conta própria.
  it 'erro ao enfileirar o do Agendamento: o da carteira ainda vai para a fila' do
    tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)
    allow(job).to receive(:perform_later).and_raise(StandardError)

    expect do
      ActiveSupport::Notifications.instrument('whatsapp_templates.consentimento_ligado', account_id: account.id, marca: 'utility')
    end.to have_enqueued_job(job_da_carteira).with(account.id)
    expect(tracker).to have_received(:capture_exception).once
  end
end
