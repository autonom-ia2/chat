require 'rails_helper'

# #2112: a queda do WhatsApp API só vira aviso se durar a carência (o motor reconecta em segundos).
RSpec.describe WhatsappHybrid::DownAlertJob do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:admin) { create(:user, account: inbox.account, role: :administrator) }
  let(:connection) do
    WhatsappHybrid::Connection.create!(account: inbox.account, inbox: inbox, session_name: 'hybrid-queda', status: 'connected',
                                       connected_phone: channel.phone_number.delete('^0-9'), risk_accepted_at: Time.current)
  end
  let(:client) { instance_double(Waha::Client) }
  let(:avisos) { Autonomia::Guide::Aviso.where(account: inbox.account, user: admin) }

  before do
    admin
    Redis::Alfred.delete(WhatsappHybrid::DownAlert.chave_da_queda(connection))
    allow(Waha::Client).to receive(:new).and_return(client)
    allow(client).to receive(:get_session).and_return({ 'status' => 'FAILED' })
    allow(client).to receive(:update_session)
  end

  def estado(status)
    WhatsappHybrid::WebhookEventJob.perform_now(connection.id, 'session.status', { 'status' => status })
  end

  def conferencias
    enqueued_jobs.select { |job| job['job_class'] == described_class.name }.map { |job| job['arguments'] }
  end

  def conferir_todas
    conferencias.each { |args| described_class.perform_now(*args) }
  end

  it 'queda que continua depois da carência avisa uma vez cada administrador, no instante da queda' do
    queda = Time.current.change(usec: 0)
    travel_to(queda) { estado('FAILED') }
    expect(conferencias.size).to eq(1)

    travel_to(queda + WhatsappHybrid::DownAlert::CARENCIA) { conferir_todas }
    travel_to(queda + WhatsappHybrid::DownAlert::CARENCIA) { conferir_todas }

    expect(avisos.count).to eq(1)
    expect(avisos.first.gravidade).to eq('urgente')
    expect(avisos.first.texto).to include(inbox.name)
    expect(connection.reload.down_alerted_at).to eq(queda)
  end

  it 'piscada (caiu e voltou antes da carência) não avisa' do
    estado('STARTING')
    estado('WORKING')

    conferir_todas

    expect(avisos.count).to eq(0)
    expect(connection.reload.down_alerted_at).to be_nil
  end

  it 'caiu, voltou e caiu de novo: só a queda mais recente conta, sem aviso adiantado' do
    inicio = Time.current.change(usec: 0)
    travel_to(inicio) { estado('FAILED') }
    travel_to(inicio + 1.minute) { estado('WORKING') }
    travel_to(inicio + 4.minutes) { estado('FAILED') }
    primeira, segunda = conferencias

    travel_to(inicio + 5.minutes) { described_class.perform_now(*primeira) }
    expect(avisos.count).to eq(0)

    travel_to(inicio + 9.minutes) { described_class.perform_now(*segunda) }
    expect(avisos.count).to eq(1)
    expect(connection.reload.down_alerted_at).to eq(inicio + 4.minutes)
  end

  it 'o webhook de volta se perdeu: a conferência pergunta ao motor e não avisa se a sessão já está funcionando' do
    estado('FAILED')
    allow(client).to receive(:get_session).and_return({ 'status' => 'WORKING', 'me' => { 'id' => "#{connection.connected_phone}@c.us" } })
    allow(client).to receive(:capping).and_return({})

    conferir_todas

    expect(avisos.count).to eq(0)
    expect(connection.reload.status).to eq('connected')
  end

  it 'motor sem resposta durante toda a carência conta como queda e avisa' do
    allow(client).to receive(:get_session).and_raise(Waha::Client::Timeout, 'sem resposta')
    WhatsappHybrid::SessionManager.new(connection).refresh!(sync_proxy: false)
    expect(connection.reload.status).to eq('disconnected')
    conferir_todas
    expect(avisos.count).to eq(1)
  end

  it 'chave velha esquecida no Redis não impede o aviso da queda nova' do
    Redis::Alfred.setex(WhatsappHybrid::DownAlert.chave_da_queda(connection), 1, 3600)

    estado('FAILED')
    conferir_todas

    expect(avisos.count).to eq(1)
  end

  it 'sem Redis para agendar, avisa na hora (queda de verdade nunca fica sem aviso)' do
    allow(Redis::Alfred).to receive(:setex).and_raise(Redis::CannotConnectError)

    estado('FAILED')

    expect(conferencias).to be_empty
    expect(avisos.count).to eq(1)
  end

  it 'a caixa voltou entre a conferência e o aviso: não marca nem avisa' do
    estado('FAILED')
    marco = conferencias.first.last
    connection.reload.update!(status: 'connected')

    WhatsappHybrid::DownAlert.new(connection).avisar!(marco)

    expect(avisos.count).to eq(0)
    expect(connection.reload.down_alerted_at).to be_nil
  end

  it 'caixa pausada durante a carência não avisa' do
    estado('FAILED')
    connection.update!(paused_at: Time.current)

    conferir_todas

    expect(avisos.count).to eq(0)
  end
end
