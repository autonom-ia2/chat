require 'rails_helper'

# Envio dos avisos (#1192): J5-A1 (texto dentro da janela, modelo aprovado fora), J5-A4 (falha registra e avisa,
# nunca altera a reunião), #1270 (WAHA sem janela de 24 h, com os tetos), J2-A9/RA-18 (toda mensagem tem como parar, quem parou
# não recebe), tetos e kill-switch.
RSpec.describe Crm::BookingV2::Notices::Sender do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:world) { build_booking_world(account: account) }
  let(:booked_template) do
    { 'name' => 'aviso_marcado', 'status' => 'APPROVED', 'language' => 'pt_BR', 'category' => 'UTILITY',
      'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, seu horário é {{2}}. Gerencie aqui: {{3}}' }] }
  end
  let(:inbox) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false,
                              message_templates: [booked_template]).inbox
  end
  let(:meeting) do
    create_internal_meeting(world: world, starts_at: Time.zone.parse('2026-10-20T13:00:00Z'),
                            metadata: { 'booking_profile_id' => world.profile.id })
  end
  let!(:invite) { create_booking_invite(world: world, meeting: meeting, scheduled_at: Time.current, channel: 'public') }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true', 'FRONTEND_URL' => 'https://app.example.com') do
      travel_to(Time.zone.parse('2026-10-12T14:00:00Z')) { example.run }
    end
  end

  before do
    account.enable_features('crm_booking_v2')
    account.save!
    world.profile.update!(notice_inbox: inbox)
  end

  # Aviso já tomado pelo cron, no vencimento que o Scheduler daria (lembrete: início menos a antecedência).
  def claimed(kind = 'booked', due_at: Crm::BookingV2::Notices::Scheduler.expected_due_at(meeting, kind))
    Crm::MeetingNotice.create!(meeting: meeting, account: account, kind: kind, due_at: due_at, status: :sending, attempts: 1)
  end

  def open_window!(at: 2.hours.ago, target_inbox: inbox)
    conversation = create(:conversation, account: account, inbox: target_inbox, contact: world.contact)
    create(:message, account: account, inbox: target_inbox, conversation: conversation, message_type: :incoming, created_at: at)
    conversation
  end

  def alerts
    Crm::FollowUp.where(account_id: account.id).where("metadata->>'source' = ?", 'booking_agent_alert')
  end

  def meeting_snapshot
    meeting.reload.attributes.slice('status', 'starts_at', 'ends_at', 'confirmation_status', 'reminders_stopped_at')
  end

  describe 'WhatsApp oficial (J5-A1)' do
    # #1517: dentro da janela o link de gestão vai no botão "Ver meu horário" (sender_button_spec.rb). #1562: a saída
    # de parar (J2-A9) vai na mensagem 2, com o botão "Parar avisos"; a 1 sai sem a linha de parar.
    it 'manda texto dentro da janela de 24 h, com o botão do link de gestão e o "Parar avisos" na mensagem 2 (J2-A9)' do
      conversation = open_window!
      notice = claimed

      described_class.new(notice).perform

      message = Message.find(notice.reload.message_id)
      expect(notice).to have_attributes(status: 'sent', sent_at: Time.current, skip_reason: nil, error_code: nil)
      expect(message).to have_attributes(conversation_id: conversation.id, message_type: 'outgoing')
      expect(message.additional_attributes.to_h['template_params']).to be_nil
      expect(message.content).to eq('Oi, Marcos! Seu horário está marcado para 20/10 às 10:00.')
      expect(message.content_attributes['crm_booking_notice']).to be(true)
      expect(message.content_attributes['rich_message']).to eq('type' => 'link_button', 'label' => 'Ver meu horário', 'url' => invite.url)
      stop = conversation.messages.outgoing.order(:id).last
      expect(stop.content_attributes['rich_message']).to eq('type' => 'link_button', 'label' => 'Parar avisos',
                                                            'url' => "#{invite.url}?stop_notices=1")
    end

    it 'fora da janela manda o modelo aprovado, com as três variáveis, numa conversa nova se não houver' do
      world.profile.update!(notice_templates: { 'booked' => { 'name' => 'aviso_marcado', 'language' => 'pt_BR' } })
      notice = claimed

      expect { described_class.new(notice).perform }.to change(Conversation, :count).by(1)

      message = Message.find(notice.reload.message_id)
      expect(notice.status).to eq('sent')
      expect(message.conversation).to have_attributes(inbox_id: inbox.id, contact_id: world.contact.id)
      expect(message.additional_attributes['template_params']).to eq(
        'name' => 'aviso_marcado', 'language' => 'pt_BR',
        'processed_params' => { 'body' => { '1' => 'Marcos', '2' => '20/10 às 10:00', '3' => invite.url } }
      )
      expect(message.content).to eq("Oi Marcos, seu horário é 20/10 às 10:00. Gerencie aqui: #{invite.url}")
      # #1270: abrir conversa no oficial não pergunta nada à WAHA.
      expect(a_request(:get, %r{/api/contacts/check-exists})).not_to have_been_made
    end

    it 'fora da janela e sem modelo aprovado pula com template_required, avisa o agente uma vez e não mexe na reunião (J2-A6, J5-A4)' do
      before = meeting_snapshot
      first = claimed('booked')
      second = claimed('day_before')

      expect do
        described_class.new(first).perform
        described_class.new(second).perform
      end.not_to change(Message, :count)

      expect([first.reload, second.reload].map { |notice| [notice.status, notice.skip_reason] }).to eq([%w[skipped template_required]] * 2)
      expect(alerts.count).to eq(1)
      expect(alerts.sole).to have_attributes(assignee_id: world.host.id, follow_up_type: 'task', card_id: world.card.id)
      failures = Crm::Activity.where(card_id: world.card.id, event_type: 'booking_notice_failed')
      expect(failures.count).to eq(2)
      expect(failures.map { |activity| activity.payload['by'] }).to eq(%w[system system])
      expect(meeting_snapshot).to eq(before)
    end

    it 'modelo aprovado sem {{3}} (sem link de gestão nem de parar) não sai: template_without_link e avisa o agente (J2-A9, RA-18)' do
      no_link = booked_template.merge('components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, seu horário é {{2}}.' }])
      inbox.channel.update!(message_templates: [no_link])
      world.profile.update_columns(notice_templates: { 'booked' => { 'name' => 'aviso_marcado', 'language' => 'pt_BR' } }) # rubocop:disable Rails/SkipsModelValidations
      notice = claimed

      expect { described_class.new(notice).perform }.not_to change(Message, :count)

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'template_without_link')
      expect(alerts.count).to eq(1)
    end

    it 'modelo aprovado que pede mais do que o aviso preenche não sai: template_unsupported e avisa o agente' do
      asks_more = [
        [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, {{2}}. Link: {{3}}. Código {{4}}' }],
        [{ 'type' => 'HEADER', 'format' => 'TEXT', 'text' => 'Olá {{1}}' }, { 'type' => 'BODY', 'text' => 'Oi {{1}}, {{2}}: {{3}}' }],
        [{ 'type' => 'HEADER', 'format' => 'IMAGE' }, { 'type' => 'BODY', 'text' => 'Oi {{1}}, {{2}}: {{3}}' }],
        [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, {{2}}: {{3}}' },
         { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'URL', 'url' => 'https://x.example/{{1}}' }] }]
      ]
      world.profile.update_columns(notice_templates: { 'booked' => { 'name' => 'aviso_marcado', 'language' => 'pt_BR' } }) # rubocop:disable Rails/SkipsModelValidations

      asks_more.each do |components|
        inbox.channel.update!(message_templates: [booked_template.merge('components' => components)])
        notice = claimed

        expect { described_class.new(notice).perform }.not_to change(Message, :count)
        expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'template_unsupported'), components.inspect
        notice.destroy!
      end
      expect(alerts.count).to eq(1)
    end

    it 'modelo configurado mas NÃO aprovado na Meta conta como sem modelo' do
      inbox.channel.update!(message_templates: [booked_template.merge('status' => 'PENDING')])
      world.profile.update!(notice_templates: { 'booked' => { 'name' => 'aviso_marcado', 'language' => 'pt_BR' } })
      notice = claimed

      described_class.new(notice).perform

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'template_required')
    end
  end

  # #1270: pela WAHA o aviso sai sem exigir mensagem do cliente nas últimas 24 h; os tetos, o "Parar avisos" e a flag
  # da conta continuam segurando.
  describe 'WAHA (#1270, sem janela de 24 h)' do
    let(:inbox) do
      create(:channel_api, account: account, additional_attributes: { 'provider' => 'waha', 'session' => '5511900001111' }).inbox
    end
    let(:check_url) { 'https://waha.test/api/contacts/check-exists' }

    around do |example|
      with_modified_env('WAHA_API_URL' => 'https://waha.test', 'WAHA_API_KEY' => 'chave-waha-teste') { example.run }
    end

    # WAHA falsa: responde a consulta do telefone do contato do mundo pela sessão da caixa.
    def waha_answers(body)
      stub_request(:get, check_url).with(query: { phone: '5511912345678', session: '5511900001111' })
                                   .to_return(status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    def other_waha_inbox
      create(:channel_api, account: account, additional_attributes: { 'provider' => 'waha', 'session' => 'outra' }).inbox
    end

    def waha_sent_elsewhere(count, at:)
      count.times do |index|
        other = create_internal_meeting(world: world, starts_at: Time.zone.parse('2026-10-25T13:00:00Z') + index.days)
        Crm::MeetingNotice.create!(meeting: other, account: account, kind: 'booked', due_at: at, status: :sent, sent_at: at)
      end
    end

    it 'manda texto na conversa que já existe, mesmo sem mensagem do cliente nas últimas 24 h, sem perguntar à WAHA' do
      conversation = open_window!(at: 25.hours.ago)
      notice = claimed

      described_class.new(notice).perform

      expect(notice.reload).to have_attributes(status: 'sent', skip_reason: nil)
      message = Message.find(notice.message_id)
      expect(message).to have_attributes(conversation_id: conversation.id, content_attributes: include('crm_booking_notice' => true))
      expect(message.content).to include(invite.url)
      expect(alerts.count).to eq(0)
      expect(a_request(:get, check_url)).not_to have_been_made
    end

    it 'sem conversa: pergunta o chat id à WAHA, grava nos atributos do contato como a WAHA grava, abre a conversa e manda' do
      check = waha_answers(numberExists: true, chatId: '551112345678@c.us')
      notice = claimed

      expect { described_class.new(notice).perform }.to change(Conversation, :count).by(1)

      expect(check).to have_been_made.once
      conversation = Message.find(notice.reload.message_id).conversation
      expect(notice.status).to eq('sent')
      expect(conversation).to have_attributes(inbox_id: inbox.id, contact_id: world.contact.id)
      # O número brasileiro sem o 9º dígito vem da WAHA: é ele que vale, não o telefone digitado.
      expect(world.contact.reload.custom_attributes).to include('waha_whatsapp_chat_id' => '551112345678@c.us',
                                                                'waha_whatsapp_jid' => '551112345678@c.us')
      expect(conversation.contact_inbox.source_id).to be_present
    end

    it 'chat id @lid vira o chat id do contato e vai para waha_whatsapp_lid; jid e outros atributos ficam' do
      world.contact.update!(custom_attributes: { 'waha_whatsapp_jid' => '5511912345678@c.us', 'waha_whatsapp_chat_id' => 'antigo@c.us',
                                                 'origem' => 'site' })
      waha_answers(numberExists: true, chatId: '123456789@lid')

      described_class.new(claimed).perform

      expect(world.contact.reload.custom_attributes).to eq(
        'origem' => 'site', 'waha_whatsapp_jid' => '5511912345678@c.us',
        'waha_whatsapp_chat_id' => '123456789@lid', 'waha_whatsapp_lid' => '123456789@lid'
      )
    end

    it 'reaproveita o ContactInbox que o contato já tem nesta caixa (sem conversa aberta)' do
      contact_inbox = ContactInboxBuilder.new(contact: world.contact, inbox: inbox, source_id: nil).perform
      waha_answers(numberExists: true, chatId: '5511912345678@c.us')
      notice = claimed

      expect { described_class.new(notice).perform }.not_to change(ContactInbox, :count)

      expect(Message.find(notice.reload.message_id).conversation.contact_inbox_id).to eq(contact_inbox.id)
    end

    it 'número sem WhatsApp: não abre conversa, pula com no_whatsapp e avisa o agente com o motivo em texto simples' do
      waha_answers(numberExists: false)
      notice = claimed

      expect { described_class.new(notice).perform }.not_to change(Conversation, :count)

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'no_whatsapp')
      expect(ContactInbox.where(inbox: inbox)).to be_empty
      expect(world.contact.reload.custom_attributes).not_to have_key('waha_whatsapp_chat_id')
      expect(alerts.sole.title).to end_with('O número do cliente não tem WhatsApp.')
    end

    def waha_fails(response = { status: 500, body: 'erro' })
      stub = stub_request(:get, check_url).with(query: hash_including(session: '5511900001111'))
      response == :timeout ? stub.to_raise(Net::ReadTimeout) : stub.to_return(response)
    end

    # O cron toma o aviso de novo numa rodada seguinte, em `at`. (`travel_to` sem bloco: o `around` já viaja no tempo
    # e desfaz tudo no fim do exemplo.)
    def next_round(notice, at:)
      travel_to(at)
      notice.reload.update!(status: :sending, attempts: notice.attempts + 1)
      described_class.new(notice).perform
    end

    it 'WAHA com erro: não abre conversa, não chama o agente e devolve o aviso à fila para a próxima rodada' do
      check = waha_fails
      notice = claimed

      expect { described_class.new(notice).perform }.not_to change(Conversation, :count)

      expect(check).to have_been_made.once
      expect(notice.reload).to have_attributes(status: 'pending', skip_reason: nil, error_code: 'waha_unavailable', message_id: nil)
      expect(alerts.count).to eq(0)
    end

    it 'WAHA sem resposta (timeout): devolve o aviso à fila, sem abrir conversa nem chamar o agente' do
      waha_fails(:timeout)
      notice = claimed

      expect { described_class.new(notice).perform }.not_to change(Conversation, :count)

      expect(notice.reload).to have_attributes(status: 'pending', error_code: 'waha_unavailable')
      expect(alerts.count).to eq(0)
    end

    it 'a consulta usa o timeout curto, não o padrão do cliente' do
      client = instance_double(Waha::Client)
      allow(Waha::Client).to receive(:new).and_return(client)
      allow(client).to receive(:check_contact_exists).and_return('numberExists' => true, 'chatId' => '5511912345678@c.us')

      described_class.new(claimed).perform

      expect(client).to have_received(:check_contact_exists).with(phone: '5511912345678', session: '5511900001111', timeout: 5)
    end

    it 'quando a WAHA volta, o aviso devolvido sai na rodada seguinte e a marca da espera some' do
      waha_fails
      notice = claimed
      described_class.new(notice).perform
      WebMock.reset!
      waha_answers(numberExists: true, chatId: '5511912345678@c.us')

      next_round(notice, at: 1.minute.from_now)

      expect(notice.reload).to have_attributes(status: 'sent', error_code: nil, skip_reason: nil)
      expect(Message.find(notice.message_id).conversation.inbox_id).to eq(inbox.id)
      expect(alerts.count).to eq(0)
    end

    it '"ao marcar": passadas 2 h do vencimento com a WAHA fora, pula com waha_unavailable e avisa o agente uma vez' do
      waha_fails
      notice = claimed
      described_class.new(notice).perform
      next_round(notice, at: notice.due_at + 119.minutes)
      expect(notice.reload.status).to eq('pending')
      expect(alerts.count).to eq(0)

      next_round(notice, at: notice.due_at + 121.minutes)

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'waha_unavailable', message_id: nil)
      expect(alerts.sole.title).to end_with('O WhatsApp não oficial não respondeu: confira se ele está conectado.')
    end

    it '"1 dia antes": tenta até 6 h antes da reunião; depois pula e avisa' do
      waha_fails
      notice = claimed('day_before')

      next_round(notice, at: meeting.starts_at - 6.hours - 1.minute)
      expect(notice.reload.status).to eq('pending')

      next_round(notice, at: meeting.starts_at - 6.hours + 1.minute)
      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'waha_unavailable')
      expect(alerts.count).to eq(1)
    end

    it '"1 hora antes": tenta até o início; começada a reunião, pula com waha_unavailable (não past_due) e avisa' do
      waha_fails
      notice = claimed('hour_before')

      next_round(notice, at: meeting.starts_at - 1.minute)
      expect(notice.reload.status).to eq('pending')

      next_round(notice, at: meeting.starts_at + 1.minute)
      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'waha_unavailable')
      expect(alerts.count).to eq(1)
    end

    it 'na mesma rodada, depois de uma falha do servidor a WAHA não é consultada de novo e os avisos voltam à fila' do
      check = waha_fails(:timeout)
      outage = Crm::BookingV2::Notices::WahaOutage.new
      first = claimed
      second = claimed('rescheduled')

      described_class.new(first, waha_outage: outage).perform
      described_class.new(second, waha_outage: outage).perform

      expect(check).to have_been_made.once
      expect([first, second].map { |notice| notice.reload.status }).to eq(%w[pending pending])
      expect(alerts.count).to eq(0)
      # O servidor WAHA é um só: timeout, sem conexão ou 5xx tiram todas as caixas WAHA da rodada.
      expect([outage.down?(inbox), outage.down?(other_waha_inbox)]).to eq([true, true])
    end

    it 'resposta fora do formato é problema da sessão: só essa caixa sai da rodada' do
      waha_answers(numberExists: true)
      outage = Crm::BookingV2::Notices::WahaOutage.new

      described_class.new(claimed, waha_outage: outage).perform

      expect([outage.down?(inbox), outage.down?(other_waha_inbox)]).to eq([true, false])
    end

    it '429 (e 408, 425) é passageiro: o aviso volta à fila, sem alertar e sem tirar a WAHA da rodada' do
      [429, 408, 425].each do |status|
        WebMock.reset!
        check = waha_fails(status: status, body: 'calma')
        outage = Crm::BookingV2::Notices::WahaOutage.new
        notice = claimed
        other = claimed('rescheduled')

        described_class.new(notice, waha_outage: outage).perform
        described_class.new(other, waha_outage: outage).perform

        expect(check).to have_been_made.twice
        expect([notice, other].map { |item| item.reload.status }).to eq(%w[pending pending]), "status #{status}"
        expect(notice.error_code).to eq('waha_unavailable')
        expect(outage.down?(inbox)).to be(false)
        Crm::MeetingNotice.delete_all
      end
      expect(alerts.count).to eq(0)
    end

    it 'WAHA que recusa o pedido (outros 4xx): waha_refused na hora, com o motivo no alerta, sem marcar a WAHA nem voltar à fila' do
      waha_fails(status: 422, body: 'telefone recusado')
      outage = Crm::BookingV2::Notices::WahaOutage.new
      notice = claimed

      described_class.new(notice, waha_outage: outage).perform

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'waha_refused')
      expect(outage.down?(inbox)).to be(false)
      expect(alerts.sole.title).to end_with('O WhatsApp não oficial recusou a consulta deste número.')
    end

    it 'orçamento da rodada: somados 20 s de consulta, o resto volta à fila sem consultar a WAHA' do
      check = waha_answers(numberExists: false)
      ticks = [0, 12, 12, 24].each
      outage = Crm::BookingV2::Notices::WahaOutage.new(clock: -> { ticks.next })
      slow = [claimed, claimed('rescheduled')]
      late = claimed('day_before')

      (slow + [late]).each { |notice| described_class.new(notice, waha_outage: outage).perform }

      expect(check).to have_been_made.twice
      expect(slow.map { |notice| notice.reload.skip_reason }).to eq(%w[no_whatsapp no_whatsapp])
      expect(late.reload).to have_attributes(status: 'pending', error_code: 'waha_unavailable')
    end

    it 'só devolve à fila o aviso que ainda é o sending desta tentativa' do
      notice = claimed
      stub_request(:get, check_url).with(query: hash_including(session: '5511900001111')).to_return do
        # Outro processo deu o aviso por preso enquanto a WAHA respondia.
        Crm::MeetingNotice.where(id: notice.id).update_all(status: Crm::MeetingNotice.statuses[:failed], error_code: 'interrupted') # rubocop:disable Rails/SkipsModelValidations
        { status: 500, body: 'erro' }
      end

      described_class.new(notice).perform

      expect(notice.reload).to have_attributes(status: 'failed', error_code: 'interrupted')
    end

    it 'aviso que esperava a WAHA e é pulado por outro motivo não guarda a marca da espera' do
      waha_fails
      notice = claimed
      described_class.new(notice).perform
      expect(notice.reload.error_code).to eq('waha_unavailable')
      Crm::BookingNoticeStop.create!(account: account, contact: world.contact)

      next_round(notice, at: 1.minute.from_now)

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'stopped', error_code: nil)
      expect(alerts.count).to eq(0)
    end

    it 'caixa WAHA sem sessão não muda sozinha: pula na hora com waha_unavailable, sem chamar a WAHA nem voltar à fila' do
      inbox.channel.update!(additional_attributes: { 'provider' => 'waha' })
      notice = claimed

      described_class.new(notice).perform

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'waha_unavailable')
      expect(a_request(:get, check_url)).not_to have_been_made
    end

    it 'integração WAHA sem configuração (sem chave no ambiente): pula com waha_unavailable sem chamar a WAHA' do
      notice = claimed

      with_modified_env('WAHA_API_KEY' => '') { described_class.new(notice).perform }

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'waha_unavailable')
      expect(a_request(:get, check_url)).not_to have_been_made
    end

    it 'WAHA que diz que o número existe mas não manda o chat id: falha da WAHA (volta à fila), não no_whatsapp' do
      waha_answers(numberExists: true)
      notice = claimed

      expect { described_class.new(notice).perform }.not_to change(Conversation, :count)

      expect(notice.reload).to have_attributes(status: 'pending', error_code: 'waha_unavailable')
    end

    it 'no_whatsapp continua definitivo: não volta à fila, mesmo dentro do limite' do
      waha_answers(numberExists: false)
      notice = claimed

      described_class.new(notice).perform

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'no_whatsapp', error_code: nil)
    end

    it '#will_send? não espera a WAHA (a tela pública não chama o motor)' do
      expect(described_class.new(claimed).will_send?).to be(true)
      expect(a_request(:get, check_url)).not_to have_been_made
    end

    it 'sem conversa e sem telefone no contato, pula com no_phone e avisa o agente' do
      world.contact.update!(phone_number: nil)
      notice = claimed

      expect { described_class.new(notice).perform }.not_to change(Message, :count)

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'no_phone')
      expect(alerts.count).to eq(1)
    end

    it 'teto por número segura sem a janela: o 5º aviso automático em 24 h não sai' do
      waha_sent_elsewhere(4, at: 2.hours.ago)
      notice = claimed

      expect { described_class.new(notice).perform }.not_to change(Message.outgoing, :count)

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'number_cap')
    end

    it 'teto por número conta os testes de "Testar no meu WhatsApp" também pela WAHA' do
      waha_sent_elsewhere(3, at: 2.hours.ago)
      create_booking_invite(world: world, metadata: { 'test' => true }, sent_at: 1.hour.ago)
      notice = claimed

      described_class.new(notice).perform

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'number_cap')
    end

    it 'teto por conta segura sem a janela' do
      other = create_internal_meeting(world: world, starts_at: Time.zone.parse('2026-10-21T13:00:00Z'))
      Crm::MeetingNotice.create!(meeting: other, account: account, kind: 'booked', due_at: 1.hour.ago, status: :sent, sent_at: 1.hour.ago)
      notice = claimed

      expect do
        with_modified_env('CRM_BOOKING_NOTICES_ACCOUNT_DAILY_LIMIT' => '1') { described_class.new(notice).perform }
      end.not_to change(Message.outgoing, :count)

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'account_cap')
    end

    it 'contato que parou os avisos não recebe pela WAHA' do
      Crm::BookingNoticeStop.create!(account: account, contact: world.contact)
      notice = claimed

      expect { described_class.new(notice).perform }.not_to change(Message.outgoing, :count)

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'stopped')
    end

    it 'com a flag crm_booking_v2 desligada nada muda: não sai, não abre conversa e will_send? é falso' do
      account.disable_features('crm_booking_v2')
      account.save!
      notice = claimed

      expect(described_class.new(notice).will_send?).to be(false)
      expect { described_class.new(notice).perform }.not_to change(Conversation, :count)

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'disabled', message_id: nil)
      expect(Message.outgoing.count).to eq(0)
      expect(a_request(:get, check_url)).not_to have_been_made
    end
  end

  describe 'canal API de campanhas, não WAHA' do
    let(:inbox) do
      create(:channel_api, account: account,
                           additional_attributes: { 'campaign_channel_type' => 'whatsapp_api', 'whatsapp_api_provider' => 'evolution' }).inbox
    end
    let!(:api_template) do
      account.whatsapp_api_message_templates.create!(inbox: inbox, name: 'lembrete', created_by: world.host,
                                                     body: 'Oi {{contact.first_name}}, lembrete do seu horário.')
    end

    it 'fora da janela manda o modelo do canal por id, com dia, link e linha de parar' do
      world.profile.update!(notice_templates: { 'booked' => { 'id' => api_template.id } })
      notice = claimed

      described_class.new(notice).perform

      expect(Message.find(notice.reload.message_id).content).to eq(
        "Oi Marcos, lembrete do seu horário.\n\n20/10 às 10:00 - #{invite.url}\n\nPara parar estes avisos: #{invite.url}?stop_notices=1"
      )
      # #1270: o canal API (Evolution) não passa pela consulta da WAHA.
      expect(a_request(:get, %r{/api/contacts/check-exists})).not_to have_been_made
    end

    it 'sem modelo e fora da janela pula com template_required' do
      notice = claimed

      described_class.new(notice).perform

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'template_required')
    end
  end

  describe 'parada (J5-A7, RA-18), na precedência opted_out, parar avisos, reunião parada' do
    before { open_window! }

    it 'contato que recusou mensagens ativas não recebe' do
      world.contact.update!(opted_out_at: Time.current, opt_out_source: 'manual')
      Crm::BookingNoticeStop.create!(account: account, contact: world.contact)
      notice = claimed

      described_class.new(notice).perform

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'opted_out')
      expect(alerts).to be_empty
    end

    it 'contato que parou os avisos não recebe, em reunião nenhuma' do
      Crm::BookingNoticeStop.create!(account: account, contact: world.contact)
      notice = claimed

      expect { described_class.new(notice).perform }.not_to change(Message.outgoing, :count)

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'stopped')
    end

    it 'reunião com avisos parados não recebe' do
      meeting.update!(reminders_stopped_at: Time.current)
      notice = claimed

      described_class.new(notice).perform

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'stopped')
    end
  end

  describe 'reunião e conta' do
    before { open_window! }

    it 'reunião cancelada não recebe aviso e não chama o agente' do
      meeting.update!(status: :canceled)
      notice = claimed('day_before')

      described_class.new(notice).perform

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'canceled')
      expect(alerts).to be_empty
    end

    it 'lembrete de reunião que já começou não sai' do
      meeting.update_columns(starts_at: 1.minute.ago, ends_at: 29.minutes.from_now) # rubocop:disable Rails/SkipsModelValidations
      notice = claimed('hour_before')

      described_class.new(notice).perform

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'past_due')
    end

    it '"ao marcar" e "remarcado" atrasados não saem depois do início da reunião, sem chamar o agente' do
      meeting.update_columns(starts_at: 1.minute.ago, ends_at: 29.minutes.from_now) # rubocop:disable Rails/SkipsModelValidations
      notices = %w[booked rescheduled].map { |kind| claimed(kind, due_at: 20.minutes.ago) }

      expect { notices.each { |notice| described_class.new(notice).perform } }.not_to change(Message, :count)

      expect(notices.map { |notice| notice.reload.skip_reason }).to eq(%w[past_due past_due])
      expect(alerts).to be_empty
    end

    it 'lembrete cujo vencimento não bate mais com o início da reunião não sai (stale), sem chamar o agente' do
      notice = claimed('hour_before', due_at: meeting.starts_at - 3.hours)

      expect { described_class.new(notice).perform }.not_to change(Message, :count)

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'stale')
      expect(alerts).to be_empty
    end

    it 'flag da conta desligada é o kill-switch: nada sai' do
      account.disable_features('crm_booking_v2')
      account.save!
      notice = claimed

      expect { described_class.new(notice).perform }.not_to change(Message.outgoing, :count)

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'disabled')
    end

    it 'página sem caixa de avisos pula com no_inbox e avisa o agente' do
      world.profile.update!(notice_inbox: nil)
      notice = claimed

      described_class.new(notice).perform

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'no_inbox')
      expect(alerts.count).to eq(1)
    end
  end

  describe 'tetos' do
    before { open_window! }

    # Avisos já enviados ao mesmo contato em outras reuniões dele (o teto é por número, não por reunião).
    def sent_elsewhere(count, at:)
      count.times do |index|
        other = create_internal_meeting(world: world, starts_at: Time.zone.parse('2026-10-25T13:00:00Z') + index.days)
        Crm::MeetingNotice.create!(meeting: other, account: account, kind: 'booked', due_at: at, status: :sent, sent_at: at)
      end
    end

    it 'para no 5º aviso automático ao mesmo número em 24 h, somando os testes de "Testar no meu WhatsApp"' do
      sent_elsewhere(3, at: 2.hours.ago)
      create_booking_invite(world: world, metadata: { 'test' => true }, sent_at: 1.hour.ago)
      notice = claimed

      described_class.new(notice).perform

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'number_cap')
    end

    it 'aviso de mais de 24 h não conta' do
      sent_elsewhere(4, at: 25.hours.ago)
      notice = claimed

      described_class.new(notice).perform

      expect(notice.reload.status).to eq('sent')
    end

    it 'o próprio aviso (já em sending) não conta no teto' do
      sent_elsewhere(3, at: 2.hours.ago)
      notice = claimed

      described_class.new(notice).perform

      expect(notice.reload.status).to eq('sent')
    end

    it 'aviso saindo agora em outro processo (sending) conta no teto' do
      sent_elsewhere(3, at: 2.hours.ago)
      other = create_internal_meeting(world: world, starts_at: Time.zone.parse('2026-10-30T13:00:00Z'))
      Crm::MeetingNotice.create!(meeting: other, account: account, kind: 'booked', due_at: Time.current, status: :sending)
      notice = claimed

      described_class.new(notice).perform

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'number_cap')
    end

    it 'teto por conta soma avisos saindo agora e testes' do
      other = create_internal_meeting(world: world, starts_at: Time.zone.parse('2026-10-21T13:00:00Z'))
      Crm::MeetingNotice.create!(meeting: other, account: account, kind: 'booked', due_at: Time.current, status: :sending)
      create_booking_invite(world: world, metadata: { 'test' => true }, sent_at: 1.hour.ago)
      notice = claimed

      with_modified_env('CRM_BOOKING_NOTICES_ACCOUNT_DAILY_LIMIT' => '2') { described_class.new(notice).perform }

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'account_cap')
    end

    it 'respeita o teto por conta configurado no ambiente' do
      other = create_internal_meeting(world: world, starts_at: Time.zone.parse('2026-10-21T13:00:00Z'))
      Crm::MeetingNotice.create!(meeting: other, account: account, kind: 'booked', due_at: 1.hour.ago, status: :sent, sent_at: 1.hour.ago)
      notice = claimed

      with_modified_env('CRM_BOOKING_NOTICES_ACCOUNT_DAILY_LIMIT' => '1') { described_class.new(notice).perform }

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'account_cap')
    end
  end

  it 'erro do envio vira failed com a classe do erro, avisa o agente e não altera a reunião (J5-A4)' do
    open_window!
    before = meeting_snapshot
    notice = claimed
    allow(Autonomia::LiteralMessageBuilder).to receive(:new).and_raise(ActiveRecord::RecordInvalid)
    tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

    described_class.new(notice).perform

    expect(notice.reload).to have_attributes(status: 'failed', error_code: 'ActiveRecord::RecordInvalid', message_id: nil)
    expect(ChatwootExceptionTracker).to have_received(:new).with(an_instance_of(ActiveRecord::RecordInvalid), account: account)
    expect(tracker).to have_received(:capture_exception).once
    expect(alerts.count).to eq(1)
    expect(meeting_snapshot).to eq(before)
  end

  describe '#will_send? (J2-A6)' do
    it 'é verdadeiro só quando o aviso de fato sairia, sem enviar nada' do
      notice = Crm::MeetingNotice.create!(meeting: meeting, account: account, kind: 'booked', due_at: Time.current)

      expect(described_class.new(notice).will_send?).to be(false)
      open_window!
      expect { expect(described_class.new(notice).will_send?).to be(true) }.not_to change(Message, :count)
      expect(notice.reload.status).to eq('pending')
    end
  end
end
