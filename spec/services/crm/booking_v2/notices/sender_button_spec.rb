require 'rails_helper'

# Botão "Ver meu horário" no aviso (#1517): só no WhatsApp oficial com a janela aberta e fora do Híbrido; texto próprio
# que já põe o link não leva botão; sem botão o link chega sempre (no texto ou na linha fixa); a saída de parar vale em
# todos os caminhos (RA-18): com botão, na mensagem 2 "Parar avisos" (#1562); sem botão, na linha de parar do texto.
RSpec.describe Crm::BookingV2::Notices::Sender do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:world) { build_booking_world(account: account) }
  let(:inbox) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false).inbox
  end
  let(:meeting) do
    create_internal_meeting(world: world, starts_at: Time.zone.parse('2026-10-20T13:00:00Z'),
                            metadata: { 'booking_profile_id' => world.profile.id })
  end
  let!(:invite) { create_booking_invite(world: world, meeting: meeting, scheduled_at: Time.current, channel: 'public') }
  let(:stop_url) { "#{invite.url}?stop_notices=1" }
  let(:stop_line) { "Para parar estes avisos: #{stop_url}" }
  let(:own_without_link) { 'Oi, {{cliente.primeiro_nome}}! Te esperamos em {{horario.data_hora}}.' }
  let(:own_with_link) { 'Oi, {{cliente.primeiro_nome}}! Te esperamos em {{horario.data_hora}}. Mude em {{horario.link_gestao}}' }

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

  def claimed(kind = 'booked')
    Crm::MeetingNotice.create!(meeting: meeting, account: account, kind: kind, status: :sending, attempts: 1,
                               due_at: Crm::BookingV2::Notices::Scheduler.expected_due_at(meeting, kind))
  end

  def open_window!(target_inbox: inbox)
    conversation = create(:conversation, account: account, inbox: target_inbox, contact: world.contact)
    create(:message, account: account, inbox: target_inbox, conversation: conversation, message_type: :incoming, created_at: 2.hours.ago)
    conversation
  end

  def sent_message
    notice = claimed
    described_class.new(notice).perform
    expect(notice.reload.status).to eq('sent')
    Message.find(notice.message_id)
  end

  def notice_messages(conversation)
    conversation.messages.outgoing.order(:id).to_a
  end

  describe 'WhatsApp oficial com a janela aberta' do
    let!(:conversation) { open_window! }

    # 1. O caso do botão (#1517 + #1562): a mensagem 1 é o aviso sem link cru e SEM a linha de parar, com "Ver meu
    # horário"; a mensagem 2 vem logo depois, na mesma conversa e do mesmo remetente, com "Parar avisos"; o aviso
    # aponta para a 1. Pega quem trocasse a ordem, juntasse as duas, mandasse a 2 em outra conversa ou perdesse a marca.
    it 'texto padrão: mensagem 1 com "Ver meu horário", sem a linha de parar, e o aviso aponta para ela' do
      notice = claimed
      expect { described_class.new(notice).perform }.to change(Message.outgoing, :count).by(2)

      first = notice_messages(conversation).first
      expect(notice.reload).to have_attributes(status: 'sent', message_id: first.id, error_code: nil)
      expect(first).to have_attributes(content: 'Oi, Marcos! Seu horário está marcado para 20/10 às 10:00.', sender: meeting.created_by)
      expect(first.content_attributes['rich_message']).to eq('type' => 'link_button', 'label' => 'Ver meu horário', 'url' => invite.url)
      expect(first.content_attributes).not_to have_key('crm_booking_notice_part')
    end

    it 'texto padrão: mensagem 2 com "Parar avisos", logo depois, na mesma conversa e do mesmo remetente' do
      notice = claimed
      described_class.new(notice).perform

      first, stop = notice_messages(conversation)
      expect(stop).to have_attributes(content: 'Não quer mais receber estes avisos?', id: be > first.id,
                                      conversation_id: first.conversation_id, sender: first.sender)
      expect(stop.content_attributes['rich_message']).to eq('type' => 'link_button', 'label' => 'Parar avisos', 'url' => stop_url)
      expect(stop.content_attributes).to include('crm_booking_notice' => true, 'crm_booking_notice_part' => 'stop',
                                                 'crm_booking_notice_id' => notice.id)
    end

    # Tetos (#1562): as duas mensagens são UM aviso. Pega quem passasse a contar mensagens em vez de avisos.
    it 'as duas mensagens contam como 1 aviso nos tetos do número e da conta' do
      sent_message

      expect(notice_messages(conversation).size).to eq(2)
      expect(described_class.recent_for_contact(world.contact)).to eq(1)
      expect(described_class.recent_for_account(account.id)).to eq(1)
    end

    # Falha da mensagem 2 na criação (#1562): a 1 já foi criada e vai sair; o aviso não vira failed, nada é refeito e o
    # responsável é avisado UMA vez (o segundo aviso da mesma reunião com o mesmo problema não cria outra tarefa).
    it 'erro ao criar a mensagem 2: a 1 fica, o aviso continua sent e o responsável é avisado uma vez' do
      allow(Crm::BookingV2::Notices::Delivery).to receive(:new).and_wrap_original do |original, **args|
        raise ActiveRecord::RecordInvalid if args[:marks].present?

        original.call(**args)
      end
      tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
      allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)
      alerts = Crm::FollowUp.where(account_id: account.id).where("metadata->>'event' = ?", 'notice_stop_failed')

      notices = %w[booked rescheduled].map { |kind| claimed(kind).tap { |notice| described_class.new(notice).perform } }

      first = Message.find(notices.first.reload.message_id)
      expect(first.content_attributes['rich_message']).to include('label' => 'Ver meu horário')
      expect(notices.map { |notice| notice.reload.attributes.slice('status', 'error_code') })
        .to all(eq('status' => 'sent', 'error_code' => 'stop_part_failed'))
      expect(notice_messages(conversation).size).to eq(2)
      expect(alerts.sole).to have_attributes(assignee_id: meeting.created_by_id)
      expect(alerts.sole.metadata).to include('reason' => 'stop_part_failed', 'kind' => 'booked')
      expect(alerts.sole.title).to include('saiu, mas a mensagem com o botão "Parar avisos" não')
      expect(tracker).to have_received(:capture_exception).twice
    end

    # fits? (#1562): a linha de parar foi para a mensagem 2, então só o corpo conta. Pega quem continuasse somando a
    # linha de parar e mandasse para o texto um aviso que cabe no botão.
    it 'corpo do tamanho exato do limite (sem a linha de parar): ainda sai com os botões' do
      stub_const('RichMessages::Types::LinkButton::BODY_MAX', 'Oi, Marcos! Seu horário está marcado para 20/10 às 10:00.'.length)

      message = sent_message

      expect(message.content_attributes['rich_message']).to include('label' => 'Ver meu horário')
      expect(notice_messages(conversation).size).to eq(2)
    end

    # 2. Texto próprio sem a chave do link: o botão leva o link.
    it 'texto próprio sem o link: botão' do
      world.profile.update!(notice_texts: { 'booked' => own_without_link })

      message = sent_message

      expect(message.content_attributes['rich_message']).to include('url' => invite.url)
      expect(message.content).to eq('Oi, Marcos! Te esperamos em 20/10 às 10:00.')
      expect(notice_messages(conversation).last.content_attributes['rich_message']).to include('label' => 'Parar avisos')
    end

    # 3. Texto próprio que põe o link: o botão duplicaria; sai como texto, com o link.
    it 'texto próprio com o link: sem botão, o texto leva o link' do
      world.profile.update!(notice_texts: { 'booked' => own_with_link })

      message = sent_message

      expect(message.content_attributes).not_to have_key('rich_message')
      expect(message.content).to eq("Oi, Marcos! Te esperamos em 20/10 às 10:00. Mude em #{invite.url}\n\n#{stop_line}")
      expect(notice_messages(conversation).size).to eq(1)
    end

    # Corpo acima do limite do botão seria recusado no envio (mensagem failed, sem link): cai no texto com o link.
    it 'corpo acima do limite do botão: sem botão, com a linha do link' do
      stub_const('RichMessages::Types::LinkButton::BODY_MAX', 40)

      message = sent_message

      expect(message.content_attributes).not_to have_key('rich_message')
      expect(message.content).to include("Para confirmar, mudar ou cancelar: #{invite.url}").and end_with(stop_line)
      expect(notice_messages(conversation).size).to eq(1)
    end
  end

  # 4. WAHA não mostra botão: o link vai no texto, como antes.
  describe 'WAHA' do
    let(:inbox) do
      create(:channel_api, account: account, additional_attributes: { 'provider' => 'waha', 'session' => '5511900001111' }).inbox
    end

    # #1562: na WAHA nada muda, byte a byte, e continua UMA mensagem.
    it 'sem rich_message, com o link e a linha de parar no texto' do
      conversation = open_window!
      message = sent_message

      expect(notice_messages(conversation)).to eq([message])

      expect(message.content_attributes).not_to have_key('rich_message')
      expect(message.content).to eq(
        "Oi, Marcos! Seu horário está marcado para 20/10 às 10:00. Para confirmar, mudar ou cancelar: #{invite.url}\n\n#{stop_line}"
      )
    end

    # 7. Texto próprio sem o link num caminho só de texto: o sistema acrescenta a linha do link antes da de parar.
    it 'texto próprio sem o link: acrescenta a linha do link antes da linha de parar' do
      world.profile.update!(notice_texts: { 'booked' => own_without_link })
      open_window!

      message = sent_message

      expect(message.content_attributes).not_to have_key('rich_message')
      expect(message.content).to eq(
        "Oi, Marcos! Te esperamos em 20/10 às 10:00.\n\nPara confirmar, mudar ou cancelar: #{invite.url}\n\n#{stop_line}"
      )
    end
  end

  # 6. 360dialog e canal API recebem só texto (RichMessages: "oficial" é só o whatsapp_cloud).
  describe 'outras caixas com a janela aberta' do
    it '360dialog: sem rich_message, link no texto' do
      dialog = create(:channel_whatsapp, account: account, provider: 'default', validate_provider_config: false, sync_templates: false).inbox
      world.profile.update!(notice_inbox: dialog)
      open_window!(target_inbox: dialog)

      message = sent_message

      expect(message.content_attributes).not_to have_key('rich_message')
      expect(message.content).to include("Para confirmar, mudar ou cancelar: #{invite.url}").and end_with(stop_line)
    end

    it 'canal API: sem rich_message, link no texto' do
      api = create(:channel_api, account: account,
                                 additional_attributes: { 'campaign_channel_type' => 'whatsapp_api', 'whatsapp_api_provider' => 'evolution' }).inbox
      world.profile.update!(notice_inbox: api)
      open_window!(target_inbox: api)

      message = sent_message

      expect(message.content_attributes).not_to have_key('rich_message')
      expect(message.content).to include("Para confirmar, mudar ou cancelar: #{invite.url}").and end_with(stop_line)
    end
  end

  # 8. A conversa que conta é a da caixa de avisos (`Route#conversation`: a do convite se é desta caixa e deste contato,
  # senão a mais recente do contato nesta caixa, em qualquer status). O cliente falou em OUTRA caixa: na de avisos não
  # há conversa, a janela dela está fechada e o aviso abre conversa nova pelo modelo, sem botão.
  describe 'cliente falou em outra caixa' do
    let(:template) do
      { 'name' => 'aviso_marcado', 'status' => 'APPROVED', 'language' => 'pt_BR', 'category' => 'UTILITY',
        'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, seu horário é {{2}}. Gerencie aqui: {{3}}' }] }
    end

    it 'conversa nova na caixa de avisos: janela fechada, modelo e nada de botão' do
      inbox.channel.update!(message_templates: [template])
      world.profile.update!(notice_templates: { 'booked' => { 'name' => 'aviso_marcado', 'language' => 'pt_BR' } })
      other = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false).inbox
      meeting.update!(conversation: open_window!(target_inbox: other))

      message = nil
      expect { message = sent_message }.to change(Conversation, :count).by(1)

      expect(message.conversation).to have_attributes(inbox_id: inbox.id)
      expect(message.additional_attributes['template_params']).to include('name' => 'aviso_marcado')
      expect(message.content_attributes).not_to have_key('rich_message')
    end

    it 'sem conversa a janela é desconhecida: o botão não sai nem pela sessão' do
      decision = Crm::BookingV2::Notices::Route::Decision.new(mode: :session, conversation: nil)

      expect(Crm::BookingV2::Notices::Button.allowed?(decision, inbox)).to be(false)
    end
  end

  # A regra num lugar só: sessão + oficial com a janela aberta + fora do Híbrido.
  describe Crm::BookingV2::Notices::Button do
    def decision(**attrs)
      Crm::BookingV2::Notices::Route::Decision.new(mode: :session, conversation: open_window!, **attrs)
    end

    it 'libera só a sessão do oficial com a janela aberta, fora do Híbrido' do
      expect(described_class.allowed?(decision, inbox)).to be(true)
      expect(described_class.allowed?(decision(via: :hybrid_web), inbox)).to be(false)
      expect(described_class.allowed?(decision(mode: :native_template), inbox)).to be(false)
    end

    # Rótulo por tipo: reunião já marcada "Ver meu horário"; convite para marcar "Escolher horário".
    # #1562: "Parar avisos" (en "Stop reminders") também cabe nos 20 caracteres do botão.
    it 'escolhe o rótulo pelo tipo de mensagem, dentro do limite do botão nos dois idiomas' do
      labels = %w[en pt_BR].index_with do |locale|
        %i[notice invite stop].map { |kind| described_class.rich_message('https://x.test/b/AB', kind: kind, locale: locale)['label'] }
      end

      expect(labels).to eq('en' => ['See my appointment', 'Pick a time', 'Stop reminders'],
                           'pt_BR' => ['Ver meu horário', 'Escolher horário', 'Parar avisos'])
      expect(labels.values.flatten.map(&:length)).to all(be <= RichMessages::Types::LinkButton::LABEL_MAX)
    end

    # #1562: a mensagem 2 sai no idioma da conta (pergunta curta + botão), e não existe sem o botão.
    it 'mensagem 2 no idioma da conta, só com o botão' do
      stop = lambda do |locale, button: true|
        account.update!(locale: locale)
        Crm::BookingV2::Notices::Text.new(meeting: meeting.reload, invite: invite, kind: 'booked', button: button).stop_message
      end

      button = ->(label) { { 'type' => 'link_button', 'label' => label, 'url' => stop_url } }
      expect(stop.call('pt_BR')).to eq({ content: 'Não quer mais receber estes avisos?', rich_message: button.call('Parar avisos') })
      expect(stop.call('en')).to eq({ content: "Don't want these reminders anymore?", rich_message: button.call('Stop reminders') })
      expect(stop.call('pt_BR', button: false)).to be_nil
    end
  end
end
