require 'rails_helper'

# Página pública com avisos no WhatsApp (#1192): `notices_enabled` quando a página tem caixa de avisos, avisos
# agendados ao marcar e `notice_will_send` (J2-A6): a tela só promete mensagem quando o aviso vai de fato sair; sem
# janela e sem modelo a reserva continua confirmada e o agente é avisado quando o cron tenta.
RSpec.describe 'Public::Api::V2::Booking notices', type: :request do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:world) { build_booking_world(account: account) }
  let(:profile) { world.profile }
  let(:slot) { '2026-10-20T10:00:00-03:00' }
  let(:inbox) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false).inbox
  end

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true', 'FRONTEND_URL' => 'https://app.example.com') do
      example.run
    end
  end

  before do
    travel_to Time.utc(2026, 10, 12, 11, 0, 0)
    account.enable_features('crm_booking_v2')
    account.save!
    allow(Crm::Cards::Broadcaster).to receive(:broadcast)
  end

  def form_token
    Crm::BookingV2::Tokens.generate('form', { 's' => profile.slug, 't' => 10.seconds.ago.to_i }, expires_in: 2.hours)
  end

  def book(phone: '(11) 91234-5678', **extra)
    post "/public/api/v2/booking/#{profile.slug}",
         params: { name: 'Marcos Lima', phone: phone, starts_at: slot, company: '', form_token: form_token,
                   consent: { accepted: true, text_key: 'booking_v2.consent.whatsapp_notices' } }.merge(extra), as: :json
  end

  it 'notices_enabled acompanha a caixa de avisos da página' do
    get "/public/api/v2/booking/#{profile.slug}"
    expect(response.parsed_body['notices_enabled']).to be(false)

    profile.update!(notice_inbox: inbox)
    get "/public/api/v2/booking/#{profile.slug}"
    expect(response.parsed_body['notices_enabled']).to be(true)
  end

  it 'sem caixa de avisos: reserva confirmada, nenhum aviso agendado e nada prometido' do
    book

    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to include('confirmed' => true, 'notice_will_send' => false)
    expect(Crm::MeetingNotice.count).to eq(0)
  end

  it 'com caixa mas sem conversa nem modelo: agenda os avisos, reserva confirmada e não promete mensagem (J2-A6)' do
    profile.update!(notice_inbox: inbox)

    book

    meeting = Crm::Meeting.sole
    expect(response.parsed_body).to include('confirmed' => true, 'notice_will_send' => false)
    expect(meeting.status).to eq('scheduled')
    expect(meeting.notices.order(:due_at).pluck(:kind, :status)).to eq([%w[booked pending], %w[day_before pending], %w[hour_before pending]])
  end

  it 'com o cliente dentro da janela de 24 h na caixa de avisos: promete a mensagem' do
    profile.update!(notice_inbox: inbox)
    conversation = create(:conversation, account: account, inbox: inbox, contact: world.contact)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, created_at: 1.hour.ago)

    book

    expect(response.parsed_body).to include('confirmed' => true, 'notice_will_send' => true)
    expect(Crm::Meeting.sole.card.contact_id).to eq(world.contact.id)
  end

  it 'com modelo aprovado para o aviso "ao marcar": promete a mensagem mesmo sem conversa' do
    inbox.channel.update!(message_templates: [{ 'name' => 'aviso', 'language' => 'pt_BR', 'status' => 'APPROVED',
                                                'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, veja: {{3}}' }] }])
    profile.update!(notice_inbox: inbox, notice_templates: { 'booked' => { 'name' => 'aviso', 'language' => 'pt_BR' } })

    book(phone: '(21) 98888-7777')

    expect(response.parsed_body['notice_will_send']).to be(true)
  end

  it 'modelo aprovado sem {{3}} (sem link de gestão nem de parar) não promete mensagem (RA-18)' do
    profile.update!(notice_inbox: inbox, notice_templates: { 'booked' => { 'name' => 'aviso', 'language' => 'pt_BR' } })
    inbox.channel.update!(message_templates: [{ 'name' => 'aviso', 'language' => 'pt_BR', 'status' => 'APPROVED',
                                                'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}' }] }])

    book(phone: '(21) 98888-7777')

    expect(response.parsed_body).to include('confirmed' => true, 'notice_will_send' => false)
  end

  it 'reserva pelo convite guarda a conversa do convite na reunião' do
    profile.update!(notice_inbox: inbox)
    conversation = create(:conversation, account: account, inbox: inbox, contact: world.contact)
    invite = create_booking_invite(world: world, conversation: conversation)

    book(invite_code: invite.code)

    expect(Crm::Meeting.sole.conversation_id).to eq(conversation.id)
  end
end
