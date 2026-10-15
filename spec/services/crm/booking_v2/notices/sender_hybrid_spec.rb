require 'rails_helper'

# Aviso do agendamento em caixa oficial com WhatsApp Híbrido pronto (#1349, decisão do Rodrigo em 12/10): onde o modelo
# não resolve e a janela de 24 h está fechada, o aviso sai como texto e o roteador do Híbrido o manda pela WAHA
# (simulada), com os mesmos tetos e o "Parar avisos". Origem do Híbrido: `automation`.
RSpec.describe Crm::BookingV2::Notices::Sender do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:world) { build_booking_world(account: account) }
  let(:booked_template) do
    { 'name' => 'aviso_marcado', 'status' => 'APPROVED', 'language' => 'pt_BR', 'category' => 'UTILITY',
      'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, seu horário é {{2}}. Gerencie aqui: {{3}}' }] }
  end
  let(:templates) { [] }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false,
                              message_templates: templates)
  end
  let(:inbox) { channel.inbox }
  let(:meeting) do
    create_internal_meeting(world: world, starts_at: Time.zone.parse('2026-10-20T13:00:00Z'),
                            metadata: { 'booking_profile_id' => world.profile.id })
  end
  let!(:invite) { create_booking_invite(world: world, meeting: meeting, scheduled_at: Time.current, channel: 'public') }
  let(:client) { instance_double(Waha::Client) }
  let(:hybrid_status) { 'connected' }
  let(:disabled_origins) { [] }
  let(:hybrid_accounts) { account.id.to_s }
  let!(:connection) do
    WhatsappHybrid::Connection.create!(
      account: account, inbox: inbox, session_name: 'hybrid-aviso', status: hybrid_status, disabled_origins: disabled_origins,
      connected_phone: channel.phone_number.delete('^0-9'), risk_accepted_at: Time.current, status_checked_at: Time.current
    )
  end

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true', 'FRONTEND_URL' => 'https://app.example.com',
                      'WAHA_API_URL' => 'https://waha.test', 'WAHA_API_KEY' => 'chave-waha-teste',
                      'WHATSAPP_HYBRID_ACCOUNT_IDS' => hybrid_accounts) do
      travel_to(Time.zone.parse('2026-10-12T14:00:00Z')) { example.run }
    end
  end

  before do
    account.enable_features('crm_booking_v2')
    account.save!
    world.profile.update!(notice_inbox: inbox)
    WhatsappHybrid::Config.forget_inbox(inbox.id)
    allow(Waha::Client).to receive(:new).and_return(client)
    allow(client).to receive(:check_contact_exists).and_return({ 'numberExists' => true, 'chatId' => '5511912345678@c.us' })
    allow(client).to receive(:new_message_id).and_return('3EB0AVISO')
    allow(client).to receive_messages(send_text: { 'id' => 'true_5511912345678@c.us_3EB0AVISO' }, start_typing: {}, stop_typing: {},
                                      update_session: {}, capping: {})
    allow(Kernel).to receive(:sleep)
    Redis::Alfred.delete('whatsapp_hybrid:chat_id:hybrid-aviso:5511912345678')
  end

  def claimed(kind = 'booked')
    Crm::MeetingNotice.create!(meeting: meeting, account: account, kind: kind, status: :sending, attempts: 1,
                               due_at: Crm::BookingV2::Notices::Scheduler.expected_due_at(meeting, kind))
  end

  # Conversa da caixa com a última mensagem do cliente há 25 h: janela oficial fechada.
  def closed_window_conversation
    conversation = create(:conversation, account: account, inbox: inbox, contact: world.contact)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, created_at: 25.hours.ago)
    conversation
  end

  def decide(conversation: nil, template: {})
    Crm::BookingV2::Notices::Route.new(inbox: inbox, contact: world.contact, conversation: conversation, template: template).decide
  end

  def alerts
    Crm::FollowUp.where(account_id: account.id).where("metadata->>'source' = ?", 'booking_agent_alert')
  end

  describe 'decisão (Notices::Route)' do
    let!(:conversation) { closed_window_conversation }

    it 'híbrido pronto e sem modelo: texto pelo Híbrido, sem motivo de pulo' do
      decision = decide(conversation: conversation)

      expect(decision).to have_attributes(mode: :session, reason: nil, via: :hybrid_web, conversation: conversation)
      expect(decision.send?).to be(true)
    end

    it 'sem conversa (nem a indicada nem outra do contato): comportamento de antes, template_required' do
      conversation.destroy!

      expect(decide).to have_attributes(reason: 'template_required', via: nil)
    end

    it 'conversa de outra caixa ou de outro contato não vale' do
      other_inbox = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false,
                                              sync_templates: false).inbox
      other = create(:conversation, account: account, inbox: other_inbox, contact: world.contact)
      conversation.destroy!

      expect(decide(conversation: other)).to have_attributes(reason: 'template_required', via: nil)
    end

    it 'janela de 24 h aberta: texto da sessão pelo caminho oficial, sem marca do Híbrido' do
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, created_at: 1.hour.ago)

      expect(decide(conversation: conversation)).to have_attributes(mode: :session, reason: nil, via: nil)
    end

    context 'when the template is approved and adequate' do
      let(:templates) { [booked_template] }

      it 'o modelo continua primeiro' do
        decision = decide(conversation: conversation, template: { 'name' => 'aviso_marcado', 'language' => 'pt_BR' })

        expect(decision).to have_attributes(mode: :native_template, reason: nil, via: nil)
      end
    end

    {
      'template_without_link' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, seu horário é {{2}}.' }],
      'template_unsupported' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, {{2}}: {{3}} {{4}}' }]
    }.each do |problem, components|
      context "when the template would give #{problem}" do
        let(:templates) { [booked_template.merge('components' => components)] }

        it 'cai no texto pelo Híbrido' do
          decision = decide(conversation: conversation, template: { 'name' => 'aviso_marcado', 'language' => 'pt_BR' })

          expect(decision).to have_attributes(mode: :session, reason: nil, via: :hybrid_web)
        end
      end
    end

    context 'when the Hybrid is disconnected' do
      let(:hybrid_status) { 'disconnected' }

      it 'mantém o motivo de antes' do
        expect(decide(conversation: conversation)).to have_attributes(reason: 'template_required', via: nil)
      end
    end

    context 'when the account is outside the pilot' do
      let(:hybrid_accounts) { '' }

      it 'mantém o motivo de antes' do
        expect(decide(conversation: conversation)).to have_attributes(reason: 'template_required', via: nil)
      end
    end

    context 'when the automation origin is disabled on the connection' do
      let(:disabled_origins) { ['automation'] }

      it 'mantém o motivo de antes' do
        expect(decide(conversation: conversation)).to have_attributes(reason: 'template_required', via: nil)
      end
    end

    context 'when the Hybrid routing is disabled (kill switch)' do
      it 'mantém o motivo de antes' do
        with_modified_env('WHATSAPP_HYBRID_ROUTING_ENABLED' => 'false') do
          expect(decide(conversation: conversation)).to have_attributes(reason: 'template_required', via: nil)
        end
      end
    end

    context 'when the inbox has no hybrid connection' do
      it 'mantém o motivo de antes' do
        connection.destroy!
        WhatsappHybrid::Config.forget_inbox(inbox.id)

        expect(decide(conversation: conversation)).to have_attributes(reason: 'template_required', via: nil)
      end
    end

    it 'contato sem telefone real (só identificador): não vai pelo Híbrido' do
      world.contact.update_columns(phone_number: nil) # rubocop:disable Rails/SkipsModelValidations

      expect(decide(conversation: conversation)).to have_attributes(reason: 'template_required', via: nil)
    end
  end

  describe 'envio real' do
    let!(:conversation) { closed_window_conversation }

    def send_hybrid_notice!
      notice = claimed
      described_class.new(notice).perform
      message = Message.find(notice.reload.message_id)
      Whatsapp::SendOnWhatsappService.new(message: message).perform
      [notice, message.reload]
    end

    it 'o aviso vira texto sem remetente e sai pela WAHA marcado como automation' do
      _notice, message = send_hybrid_notice!

      expect(message).to have_attributes(conversation_id: conversation.id, sender: nil, content_type: 'text')
      expect(message.additional_attributes.to_h['template_params']).to be_nil
      expect(message.content).to include(invite.url).and include("#{invite.url}?stop_notices=1")
      # #1517: pelo Híbrido não há botão; o link vai no texto.
      expect(message.content_attributes).not_to have_key('rich_message')
      expect(client).to have_received(:send_text).with(session: 'hybrid-aviso', chat_id: '5511912345678@c.us', text: message.content,
                                                       id: '3EB0AVISO')
      expect(message.content_attributes).to include(
        'crm_booking_notice' => true, 'crm_booking_notice_via' => 'hybrid_web',
        'whatsapp_transport' => 'web', 'whatsapp_transport_origin' => 'automation'
      )
    end

    it 'fica sent, sem falha, sem alerta, e conta no teto do número' do
      notice, message = send_hybrid_notice!

      # #1562: o "Parar avisos" em mensagem separada é só do oficial; pelo Híbrido segue UMA mensagem, com a linha.
      expect(conversation.messages.outgoing.count).to eq(1)
      expect(message.content).to end_with("\n\nPara parar estes avisos: #{invite.url}?stop_notices=1")

      expect(notice).to have_attributes(status: 'sent', skip_reason: nil, error_code: nil)
      expect(message.status).not_to eq('failed')
      expect(alerts.count).to eq(0)
      expect(described_class.recent_for_contact(world.contact)).to eq(1)
    end

    it 'com modelo aprovado e adequado sai o modelo (Cloud), nunca o Híbrido' do
      channel.update!(message_templates: [booked_template])
      world.profile.update!(notice_templates: { 'booked' => { 'name' => 'aviso_marcado', 'language' => 'pt_BR' } })
      notice = claimed

      described_class.new(notice).perform
      message = Message.find(notice.reload.message_id)

      expect(message.additional_attributes['template_params']).to include('name' => 'aviso_marcado')
      expect(message.content_attributes).not_to include('crm_booking_notice_via')
      expect(client).not_to have_received(:send_text)
    end

    it 'teto de 4 por número em 24 h vale: pula com number_cap e não manda nada' do
      4.times do |index|
        other = create_internal_meeting(world: world, starts_at: Time.zone.parse('2026-10-25T13:00:00Z') + index.days)
        Crm::MeetingNotice.create!(meeting: other, account: account, kind: 'booked', due_at: 1.hour.ago, status: :sent, sent_at: 1.hour.ago)
      end
      notice = claimed

      expect { described_class.new(notice).perform }.not_to change(Message, :count)

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'number_cap')
      expect(client).not_to have_received(:send_text)
    end

    it 'teto da conta vale: pula com account_cap' do
      allow(described_class).to receive(:account_limit).and_return(0)
      notice = claimed

      expect { described_class.new(notice).perform }.not_to change(Message, :count)

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'account_cap')
    end

    it '"Parar avisos" do contato vale: pula com stopped e não manda nada' do
      Crm::BookingNoticeStop.create!(account: account, contact: world.contact)
      notice = claimed

      expect { described_class.new(notice).perform }.not_to change(Message, :count)

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'stopped')
      expect(client).not_to have_received(:send_text)
    end

    it 'origem desligada na conexão: pula com template_required e avisa o agente, como antes' do
      connection.update!(disabled_origins: ['automation'])
      notice = claimed

      expect { described_class.new(notice).perform }.not_to change(Message, :count)

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'template_required')
      expect(alerts.count).to eq(1)
    end

    # Corrida: o Híbrido cai entre decidir e enviar. O envio falha fora da janela (nunca vai pela Cloud) e o cron
    # que confere a entrega (`NoticeDispatchJob`) troca o aviso de `sent` para `failed: delivery_failed`.
    it 'se o Híbrido cai antes do envio, a mensagem falha e o aviso deixa de constar como entregue' do
      notice = claimed
      described_class.new(notice).perform
      message = Message.find(notice.reload.message_id)
      connection.update!(status: 'disconnected')

      Whatsapp::SendOnWhatsappService.new(message: message).perform
      Crm::BookingV2::NoticeDispatchJob.perform_now

      expect(client).not_to have_received(:send_text)
      expect(message.reload.status).to eq('failed')
      expect(notice.reload).to have_attributes(status: 'failed', error_code: 'delivery_failed')
      expect(alerts.count).to eq(1)
    end

    # Falha DURANTE o envio (não antes dele): o mesmo ponto que `router_spec.rb` já testa para `WhatsappHybrid::WebTransport`
    # (sessão revalidada como caída, erro da WAHA, timeout). A mensagem fica `failed`, nunca `sent` de mentira nem
    # `pending` para sempre: o `NoticeDispatchJob` troca o aviso de `sent` para `failed: delivery_failed` na rodada seguinte.
    def notice_message_after_send!
      notice = claimed
      described_class.new(notice).perform
      message = Message.find(notice.reload.message_id)
      yield
      Whatsapp::SendOnWhatsappService.new(message: message).perform
      Crm::BookingV2::NoticeDispatchJob.perform_now
      [notice.reload, message.reload]
    end

    it 'sessão revalidada como caída no momento do envio: delivery_failed, sem reenviar' do
      notice, message = notice_message_after_send! do
        connection.update!(status_checked_at: 5.minutes.ago)
        allow(client).to receive(:get_session).and_return({ 'status' => 'STOPPED' })
      end

      expect(client).not_to have_received(:send_text)
      expect(message.status).to eq('failed')
      expect(notice).to have_attributes(status: 'failed', error_code: 'delivery_failed')
      expect(alerts.count).to eq(1)
    end

    it 'erro da WAHA no envio: delivery_failed, sem reenviar' do
      notice, message = notice_message_after_send! do
        allow(client).to receive(:send_text).and_raise(Waha::Client::Error, 'WAHA POST /api/sendText -> 500: erro')
        allow(client).to receive(:get_session).and_return({ 'status' => 'WORKING', 'me' => { 'id' => "#{connection.connected_phone}@c.us" } })
      end

      expect(message.status).to eq('failed')
      expect(notice).to have_attributes(status: 'failed', error_code: 'delivery_failed')
      expect(alerts.count).to eq(1)
    end

    it 'timeout sem resposta da WAHA no envio: delivery_failed, sem reenviar (nunca sabemos se saiu)' do
      notice, message = notice_message_after_send! do
        allow(client).to receive(:send_text).and_raise(Waha::Client::Timeout, 'timeout')
      end

      expect(client).to have_received(:send_text).once
      expect(message.status).to eq('failed')
      expect(notice).to have_attributes(status: 'failed', error_code: 'delivery_failed')
      expect(alerts.count).to eq(1)
    end
  end
end
