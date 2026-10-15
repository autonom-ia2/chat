require 'rails_helper'

# #1453: a Meta recusa o texto da campanha com 131047 e o WhatsApp Híbrido assume o reenvio pelo WhatsApp API. No
# `ensure` da queda, a Message é relida do banco e o modelo só sai quando o Híbrido falhou de forma certa (`failed`).
# A Meta e o motor nunca são chamados de verdade (stub_graph_messages e Waha::Client dublê).
RSpec.describe CampaignJourney::ConversaAberta::QuedaHibrido, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:channel) { journey_cloud_channel(account) }
  let(:inbox) { channel.inbox }
  let(:audience) { saved_audience(account: account, user: user, content: "Nome,Celular\nAna Souza,11987654321\n") }
  let(:client) { instance_double(Waha::Client) }
  let(:numero) { '+5511987654321' }

  around { |example| with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: account.id.to_s) { example.run } }

  before do
    account.enable_features!(:campaign_open_window_text)
    WhatsappHybrid::Connection.create!(account: account, inbox: inbox, session_name: 'hybrid-1453', status: 'connected',
                                       connected_phone: channel.phone_number.delete('^0-9'), risk_accepted_at: Time.current,
                                       status_checked_at: Time.current)
    allow(Waha::Client).to receive(:new).and_return(client)
    allow(client).to receive_messages(check_contact_exists: { 'numberExists' => true, 'chatId' => '5511987654321@c.us' },
                                      new_message_id: '3EB01453', send_text: {}, start_typing: {}, stop_typing: {})
    allow(Kernel).to receive(:sleep)
    Redis::Alfred.delete('whatsapp_hybrid:chat_id:hybrid-1453:5511987654321')
  end

  # A pessoa falou com a caixa há pouco: a janela está aberta e ela recebe o texto escrito.
  def ana_falou
    contact = audience.campaign_import_rows.includes(:contact).map(&:contact).first
    contact_inbox = ContactInbox.find_or_create_by!(contact: contact, inbox: inbox) { |ci| ci.source_id = contact.phone_number.delete('+') }
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
    create(:message, account: account, inbox: inbox, conversation: conversation, sender: contact, message_type: :incoming)
  end

  def campanha_disparada
    ana_falou
    campaign = create(:campaign, account: account, inbox: inbox, audience: [], message: 'Olá {{1}}, sua apólice vence em {{2}}. {{3}}',
                                 template_params: journey_template_params)
    CampaignAudienceLink.create!(account: account, campaign: campaign, campaign_import: audience, variable_defaults: {},
                                 variable_bindings: { '1' => { 'source' => 'contact', 'value' => 'first_name' },
                                                      '2' => { 'source' => 'fixed', 'value' => '10/2026' },
                                                      '3' => { 'source' => 'fixed', 'value' => 'Equipe' } })
    CampaignFreeText.create!(account: account, campaign: campaign, content: 'Oi, {{cliente.primeiro_nome}}! Posso ajudar?')
    Whatsapp::OneoffCampaignService.new(campaign: campaign).perform
    CampaignFreeTextDelivery.find_by!(campaign_id: campaign.id)
  end

  def aviso_131047(source_id)
    Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: {
      phone_number: channel.phone_number, object: 'whatsapp_business_account',
      entry: [{ changes: [{ field: 'messages', value: { statuses: [{
        id: source_id, status: 'failed', recipient_id: '5511987654321', timestamp: Time.current.to_i.to_s,
        errors: [{ code: 131_047, title: 'Re-engagement message' }]
      }] } }] }]
    }.with_indifferent_access).perform
  end

  def tipos_enviados(sent)
    sent.select { |body| body['to'] == numero }.pluck('type')
  end

  def resultado_gravado(delivery)
    Message.find(delivery.message_id).content_attributes.to_h
  end

  it 'accepted: o Híbrido entregou o texto ao motor, o modelo não sai' do
    sent = stub_graph_messages
    delivery = campanha_disparada

    perform_enqueued_jobs(only: CampaignJourney::ConversaAberta::QuedaJob) { aviso_131047(delivery.source_id) }

    expect(client).to have_received(:send_text)
    expect(resultado_gravado(delivery)).to include('whatsapp_transport_fallback' => true, 'whatsapp_transport_outcome' => 'accepted')
    expect(tipos_enviados(sent)).to eq(%w[text])
    expect(delivery.reload.fell_back_at).to be_nil
  end

  it 'failed: nada saiu pelo Híbrido (contato sem WhatsApp), o modelo sai uma vez, com o resultado relido do banco' do
    allow(client).to receive(:check_contact_exists).and_return({ 'numberExists' => false })
    sent = stub_graph_messages
    delivery = campanha_disparada

    perform_enqueued_jobs(only: CampaignJourney::ConversaAberta::QuedaJob) { aviso_131047(delivery.source_id) }

    expect(resultado_gravado(delivery)).to include('whatsapp_transport_fallback' => true, 'whatsapp_transport_outcome' => 'failed')
    expect(tipos_enviados(sent)).to eq(%w[text template])
    expect(delivery.reload.fell_back_at).to be_present
  end

  # O 2º aviso do mesmo wamid não refaz o texto pelo WhatsApp API (o contato agora existe) nem manda outro modelo.
  it 'failed repetido: o segundo aviso não reenvia pelo Híbrido nem manda outro modelo' do
    allow(client).to receive(:check_contact_exists).and_return({ 'numberExists' => false })
    sent = stub_graph_messages
    delivery = campanha_disparada
    perform_enqueued_jobs(only: CampaignJourney::ConversaAberta::QuedaJob) { aviso_131047(delivery.source_id) }
    allow(client).to receive(:check_contact_exists).and_return({ 'numberExists' => true, 'chatId' => '5511987654321@c.us' })

    perform_enqueued_jobs(only: CampaignJourney::ConversaAberta::QuedaJob) { aviso_131047(delivery.source_id) }

    expect(client).not_to have_received(:send_text)
    expect(tipos_enviados(sent)).to eq(%w[text template])
  end

  it 'accepted repetido: o segundo aviso não reenvia pelo Híbrido' do
    stub_graph_messages
    delivery = campanha_disparada

    2.times { aviso_131047(delivery.source_id) }

    expect(client).to have_received(:send_text).once
  end

  it 'erro antes de o Híbrido chegar ao motor: a marca fica, nada saiu, o modelo sai uma vez' do
    allow(client).to receive(:new_message_id).and_raise(Redis::CannotConnectError)
    sent = stub_graph_messages
    delivery = campanha_disparada

    perform_enqueued_jobs(only: CampaignJourney::ConversaAberta::QuedaJob) do
      expect { aviso_131047(delivery.source_id) }.to raise_error(Redis::CannotConnectError)
    end

    expect(Message.find(delivery.message_id)).to be_failed
    expect(resultado_gravado(delivery)).to include('whatsapp_transport_fallback' => true)
    expect(tipos_enviados(sent)).to eq(%w[text template])
  end

  it 'erro inesperado depois de o envio ser marcado: pode ter saído, fica uncertain e sem modelo' do
    allow(client).to receive(:send_text).and_raise(RuntimeError, 'motor quebrou')
    sent = stub_graph_messages
    delivery = campanha_disparada

    expect { aviso_131047(delivery.source_id) }.to raise_error(RuntimeError, 'motor quebrou')

    expect(Message.find(delivery.message_id)).to be_failed
    expect(resultado_gravado(delivery)).to include('whatsapp_transport_fallback' => true, 'whatsapp_transport' => 'web',
                                                   'whatsapp_transport_outcome' => 'uncertain')
    expect(CampaignJourney::ConversaAberta::QuedaJob).not_to have_been_enqueued
    expect(tipos_enviados(sent)).to eq(%w[text])
  end

  it 'marca e envio marcado sem resultado (não deveria ocorrer): sem modelo, com aviso no log' do
    stub_graph_messages
    delivery = campanha_disparada
    Message.find(delivery.message_id).update!(content_attributes: { 'whatsapp_transport_fallback' => true, 'whatsapp_transport' => 'web' })
    allow(Rails.logger).to receive(:warn)

    expect { described_class.new(delivery).seguir }.not_to have_enqueued_job(CampaignJourney::ConversaAberta::QuedaJob)

    expect(Rails.logger).to have_received(:warn).with(include("delivery=#{delivery.id}", 'outcome=ausente'))
  end

  it 'failed com a campanha parada: as travas de hoje seguram o modelo' do
    allow(client).to receive(:check_contact_exists).and_return({ 'numberExists' => false })
    sent = stub_graph_messages
    delivery = campanha_disparada
    CampaignPauses::Pauser.new(delivery.campaign, source: 'manual', reason_code: 'manual').perform

    perform_enqueued_jobs(only: CampaignJourney::ConversaAberta::QuedaJob) { aviso_131047(delivery.source_id) }

    expect(tipos_enviados(sent)).to eq(%w[text])
    expect(CampaignRecipient.find(delivery.campaign_recipient_id).error_message).to eq(CampaignJourney::ConversaAberta::Envio::PAUSADA)
  end

  it 'uncertain: o motor não respondeu, pode ter saído; o modelo nunca sai e o motivo vai ao log' do
    allow(client).to receive(:send_text).and_raise(Waha::Client::Timeout)
    allow(Rails.logger).to receive(:info).and_call_original
    sent = stub_graph_messages
    delivery = campanha_disparada

    expect { aviso_131047(delivery.source_id) }.not_to have_enqueued_job(CampaignJourney::ConversaAberta::QuedaJob)

    expect(resultado_gravado(delivery)['whatsapp_transport_outcome']).to eq('uncertain')
    expect(tipos_enviados(sent)).to eq(%w[text])
    expect(Rails.logger).to have_received(:info).with(include("delivery=#{delivery.id}", 'outcome=uncertain'))
  end

  it 'throttled: o modelo não sai agora; a conferência é agendada para depois' do
    allow(WhatsappHybrid::RateLimit).to receive(:new).and_return(instance_double(WhatsappHybrid::RateLimit, exceeded?: true))
    sent = stub_graph_messages
    delivery = campanha_disparada

    expect { aviso_131047(delivery.source_id) }
      .to have_enqueued_job(CampaignJourney::ConversaAberta::ConferenciaHibridoJob).with(delivery.id, 1)

    expect(CampaignJourney::ConversaAberta::QuedaJob).not_to have_been_enqueued
    expect(resultado_gravado(delivery)['whatsapp_transport_outcome']).to eq('throttled')
    expect(tipos_enviados(sent)).to eq(%w[text])
  end

  # A nova tentativa do Híbrido (FallbackRetryJob, 15 s depois) falha de forma certa: o modelo sai uma vez, e a
  # conferência que vem depois não manda outro.
  it 'throttled e depois failed: o modelo sai uma vez' do
    rate_limit = instance_double(WhatsappHybrid::RateLimit, exceeded?: true)
    allow(WhatsappHybrid::RateLimit).to receive(:new).and_return(rate_limit)
    sent = stub_graph_messages
    delivery = campanha_disparada
    expect { aviso_131047(delivery.source_id) }.to have_enqueued_job(WhatsappHybrid::FallbackRetryJob).with(delivery.message_id)
    allow(rate_limit).to receive(:exceeded?).and_return(false)
    allow(client).to receive(:check_contact_exists).and_return({ 'numberExists' => false })

    perform_enqueued_jobs(only: CampaignJourney::ConversaAberta::QuedaJob) { WhatsappHybrid::FallbackRetryJob.perform_now(delivery.message_id) }
    perform_enqueued_jobs(only: CampaignJourney::ConversaAberta::QuedaJob) do
      CampaignJourney::ConversaAberta::ConferenciaHibridoJob.perform_now(delivery.id, 1)
    end

    expect(resultado_gravado(delivery)['whatsapp_transport_outcome']).to eq('failed')
    expect(tipos_enviados(sent)).to eq(%w[text template])
    expect(delivery.reload.fell_back_at).to be_present
  end
end
