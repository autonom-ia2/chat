# Cenário mínimo de agendamento (#1187): conta, responsável, funil, cliente com WhatsApp, card e página nova.
module BookingHelpers
  BookingWorld = Struct.new(:account, :host, :pipeline, :stage, :contact, :card, :profile, keyword_init: true)

  # Cliente só com telefone (sem e-mail), como o WhatsApp entrega.
  def create_booking_contact(account:, name: 'Marcos Lima', phone: '+5511912345678', email: nil)
    account.contacts.create!(name: name, phone_number: phone, email: email)
  end

  def create_booking_card(account:, pipeline:, stage:, contact:, **attrs)
    account.crm_cards.create!(
      { pipeline: pipeline, stage: stage, contact: contact, title: 'Marcos Lima - Agendamento', currency: 'BRL' }.merge(attrs)
    )
  end

  # Página nova (page_version 2), sem caixa de e-mail, responsável fixo.
  def create_booking_profile(account:, host:, pipeline: nil, stage: nil, **attrs)
    account.crm_agent_booking_profiles.create!(
      {
        page_version: Crm::AgentBookingProfile::NEW_PAGE,
        title: 'Conversa de 30 min',
        duration_minutes: 30,
        timezone: 'America/Sao_Paulo',
        default_assignee: host,
        default_pipeline_id: pipeline&.id,
        default_stage_id: stage&.id,
        locations: [{ 'type' => 'whatsapp_video' }],
        enabled: true
      }.merge(attrs)
    )
  end

  def build_booking_world(account:, host_name: 'Camila Torres')
    host = create(:user, account: account, role: :agent, name: host_name)
    pipeline, stage = create_crm_pipeline(account: account, user: host)
    contact = create_booking_contact(account: account)
    card = create_booking_card(account: account, pipeline: pipeline, stage: stage, contact: contact, owner: host)
    profile = create_booking_profile(account: account, host: host, pipeline: pipeline, stage: stage)
    BookingWorld.new(account: account, host: host, pipeline: pipeline, stage: stage, contact: contact, card: card, profile: profile)
  end

  # Reunião interna já agendada (sem provedor), para specs de disponibilidade, cancelamento e permissões.
  def create_internal_meeting(world:, starts_at:, duration: 30, status: :scheduled, **attrs)
    meeting = world.account.crm_meetings.new(
      {
        card: world.card, created_by: world.host, title: 'Conversa de 30 min', provider: :internal,
        online_meeting_type: :whatsapp_video, status: status, timezone: 'America/Sao_Paulo',
        starts_at: starts_at, ends_at: starts_at + duration.minutes, source: 'public_link'
      }.merge(attrs)
    )
    meeting.save!
    meeting.meeting_guests.create!(account: world.account, phone_number: world.contact.phone_number, contact: world.contact,
                                   name: world.contact.name, guest_type: :contact_guest)
    meeting
  end
end

RSpec.configure do |config|
  config.include BookingHelpers
end
