require 'rails_helper'

# Botão "Ver meu horário" no aviso (#1517): só no WhatsApp oficial com a janela aberta e fora do Híbrido; texto próprio
# que já põe o link não leva botão; sem botão o link chega sempre (no texto ou na linha fixa); a linha de parar vale em
# todos os caminhos (RA-18).
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
  let(:stop_line) { "Para parar estes avisos: #{invite.url}?stop_notices=1" }
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

  describe 'WhatsApp oficial com a janela aberta' do
    before { open_window! }

    # 1. O caso do botão: o link sai do corpo e vai no botão; a linha de parar fica.
    it 'texto padrão: botão com o link de gestão, corpo sem o link cru e com a linha de parar' do
      message = sent_message

      expect(message.content_attributes['rich_message']).to eq(
        'type' => 'link_button', 'label' => 'Ver meu horário', 'url' => invite.url
      )
      expect(message.content).to eq("Oi, Marcos! Seu horário está marcado para 20/10 às 10:00.\n\n#{stop_line}")
      expect(message.content.delete_suffix(stop_line)).not_to include(invite.url)
    end

    # 2. Texto próprio sem a chave do link: o botão leva o link.
    it 'texto próprio sem o link: botão' do
      world.profile.update!(notice_texts: { 'booked' => own_without_link })

      message = sent_message

      expect(message.content_attributes['rich_message']).to include('url' => invite.url)
      expect(message.content).to eq("Oi, Marcos! Te esperamos em 20/10 às 10:00.\n\n#{stop_line}")
    end

    # 3. Texto próprio que põe o link: o botão duplicaria; sai como texto, com o link.
    it 'texto próprio com o link: sem botão, o texto leva o link' do
      world.profile.update!(notice_texts: { 'booked' => own_with_link })

      message = sent_message

      expect(message.content_attributes).not_to have_key('rich_message')
      expect(message.content).to eq("Oi, Marcos! Te esperamos em 20/10 às 10:00. Mude em #{invite.url}\n\n#{stop_line}")
    end

    # Corpo acima do limite do botão seria recusado no envio (mensagem failed, sem link): cai no texto com o link.
    it 'corpo acima do limite do botão: sem botão, com a linha do link' do
      stub_const('RichMessages::Types::LinkButton::BODY_MAX', 40)

      message = sent_message

      expect(message.content_attributes).not_to have_key('rich_message')
      expect(message.content).to include("Para confirmar, mudar ou cancelar: #{invite.url}").and end_with(stop_line)
    end
  end

  # 4. WAHA não mostra botão: o link vai no texto, como antes.
  describe 'WAHA' do
    let(:inbox) do
      create(:channel_api, account: account, additional_attributes: { 'provider' => 'waha', 'session' => '5511900001111' }).inbox
    end

    it 'sem rich_message, com o link e a linha de parar no texto' do
      open_window!
      message = sent_message

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

    it 'rótulo dentro do limite do botão nos dois idiomas' do
      %w[en pt_BR].each do |locale|
        label = described_class.rich_message('https://x.test/b/AB', locale: locale)['label']
        expect(label.length).to be <= RichMessages::Types::LinkButton::LABEL_MAX
      end
    end
  end
end
