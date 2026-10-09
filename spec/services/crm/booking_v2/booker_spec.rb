require 'rails_helper'

RSpec.describe Crm::BookingV2::Booker do
  let(:account) { create(:account) }
  let(:world) { build_booking_world(account: account) }
  let(:profile) { world.profile }
  let(:slot) { '2026-10-20T10:00:00-03:00' }

  # Segunda-feira, 08:00 em São Paulo.
  before do
    travel_to Time.utc(2026, 10, 12, 11, 0, 0)
    allow(Crm::Cards::Broadcaster).to receive(:broadcast)
  end

  def book(**overrides)
    described_class.new(profile: profile, host: world.host, name: 'Ana Souza', phone: '(21) 98888-7777', starts_at: slot,
                        source: 'public_link', **overrides).perform
  end

  it 'cria contato, card e reunião interna sem e-mail' do
    result = book(consent: { text_key: 'booking.consent.v1' })

    expect(result.existing).to be(false)
    expect(result.contact).to have_attributes(name: 'Ana Souza', phone_number: '+5521988887777', email: nil)
    expect(result.card).to have_attributes(pipeline_id: world.pipeline.id, stage_id: world.stage.id, owner_id: world.host.id,
                                           source: 'public_link', contact_id: result.contact.id)
    expect(result.meeting).to have_attributes(provider: 'internal', online_meeting_type: 'whatsapp_video', status: 'scheduled',
                                              created_by_id: world.host.id, card_id: result.card.id, source: 'public_link',
                                              starts_at: Time.iso8601(slot), ends_at: Time.iso8601(slot) + 30.minutes)
    expect(result.meeting.metadata).to include('booking_profile_id' => profile.id,
                                               'consent' => { 'accepted_at' => '2026-10-12T11:00:00Z', 'text_key' => 'booking.consent.v1' })
    expect(result.meeting.meeting_guests.pluck(:phone_number, :email)).to eq([['+5521988887777', nil]])
    expect(Crm::Cards::Broadcaster).to have_received(:broadcast).with(result.card, Events::Types::CRM_CARD_CREATED).once
  end

  it 'não grava consentimento nem link quando eles não vêm' do
    expect(book.meeting.metadata.keys).to contain_exactly('booking_profile_id', 'reminder_minutes_before', 'location')
  end

  it 'grava página e link individual na reunião e ignora link de outra página' do
    link = profile.agent_booking_links.create!(account: account, agent: world.host)
    other_profile = create_booking_profile(account: account, host: world.host)
    foreign = other_profile.agent_booking_links.create!(account: account, agent: world.host)

    expect(book(link: link).meeting.metadata).to include('booking_profile_id' => profile.id, 'booking_link_id' => link.id)
    expect(book(link: foreign, starts_at: '2026-10-20T11:00:00-03:00').meeting.metadata).not_to have_key('booking_link_id')
  end

  it 'acha o contato pelo número sem o nono dígito e não troca o nome' do
    legacy = account.contacts.create!(name: 'Ana (cliente antiga)', phone_number: '+552188887777')

    result = book(email: 'ana@example.com')

    expect(result.contact).to eq(legacy)
    expect(legacy.reload).to have_attributes(name: 'Ana (cliente antiga)', email: nil)
    expect(result.meeting.meeting_guests.order(:id).pluck(:email, :phone_number))
      .to eq([[nil, '+5521988887777'], ['ana@example.com', nil]])
  end

  it 'não usa no contato novo um e-mail que já é de outra pessoa' do
    account.contacts.create!(name: 'Outra', email: 'ana@example.com')

    expect(book(email: 'ANA@example.com').contact.email).to be_nil
  end

  it 'aceita horário escrito em outro fuso e duração extra da página' do
    profile.update!(slot_durations: [60])

    meeting = book(starts_at: '2026-10-20T13:00:00Z', duration: 60).meeting

    expect(meeting.starts_at).to eq(Time.utc(2026, 10, 20, 13))
    expect(meeting.ends_at).to eq(Time.utc(2026, 10, 20, 14))
    expect(meeting.timezone).to eq('America/Sao_Paulo')
  end

  it 'recusa entradas inválidas com códigos nomeados e sem criar nada' do
    expect { book(name: '<b> </b>') }.to raise_error(ArgumentError, 'invalid_name')
    expect { book(phone: '123') }.to raise_error(ArgumentError, 'invalid_phone')
    expect { book(email: 'ana@') }.to raise_error(ArgumentError, 'invalid_email')
    expect { book(starts_at: 'amanhã') }.to raise_error(ArgumentError, 'invalid_starts_at')
    expect { book(duration: 45) }.to raise_error(ArgumentError, 'invalid_duration')
    expect(account.crm_meetings.count).to eq(0)
  end

  it 'recusa local fora da página e horário fora da grade sem criar nada' do
    expect { book(location_type: 'teams') }.to raise_error(ArgumentError, 'invalid_location')
    expect { book(starts_at: '2026-10-20T10:10:00-03:00') }.to raise_error(ArgumentError, 'slot_unavailable')
    expect(account.crm_meetings.count).to eq(0)
    expect(account.contacts.where(phone_number: '+5521988887777')).to be_empty
  end

  it 'limpa HTML e caracteres de controle do nome' do
    expect(book(name: "<i>Ana</i>\u0007 Souza").contact.name).to eq('Ana Souza')
  end

  it 'guarda o "&" do nome como texto, sem virar entidade HTML' do
    expect(book(name: 'Ana & Bia <b>Souza</b>').contact.name).to eq('Ana & Bia Souza')
  end

  it 'recusa responsável com função sem CRM nem agendamento' do
    role = create(:custom_role, account: account, permissions: ['report_manage'])
    world.host.account_users.find_by(account: account).update!(custom_role: role)

    expect { book }.to raise_error(ArgumentError, 'host_unavailable')
  end

  it 'respeita antecedência mínima e intervalo' do
    profile.update!(min_notice_minutes: 120, buffer_minutes: 15)
    create_internal_meeting(world: world, starts_at: Time.iso8601('2026-10-20T10:30:00-03:00'))

    expect { book(starts_at: '2026-10-12T09:00:00-03:00') }.to raise_error(ArgumentError, 'slot_unavailable')
    expect { book(starts_at: slot) }.to raise_error(ArgumentError, 'slot_unavailable')
    expect(book(starts_at: '2026-10-12T10:00:00-03:00').meeting.starts_at).to eq(Time.iso8601('2026-10-12T10:00:00-03:00'))
  end

  it 'devolve a mesma reunião em reenvio dentro de 5 minutos' do
    first = book
    travel 4.minutes
    second = book(phone: '+55 21 98888-7777')

    expect(second.existing).to be(true)
    expect(second.meeting).to eq(first.meeting)
    expect(account.crm_meetings.count).to eq(1)
    expect(Crm::Cards::Broadcaster).to have_received(:broadcast).once

    travel 2.minutes
    expect { book }.to raise_error(ArgumentError, 'slot_unavailable')
  end

  it 'recusa a terceira reunião aberta do mesmo telefone' do
    book(starts_at: '2026-10-20T09:00:00-03:00')
    book(starts_at: '2026-10-20T11:00:00-03:00')

    expect { book(starts_at: '2026-10-21T11:00:00-03:00') }.to raise_error(ArgumentError, 'too_many_open')
    expect(account.crm_meetings.count).to eq(2)
  end

  it 'conta reunião passada ou cancelada fora do limite' do
    meeting = book(starts_at: '2026-10-20T09:00:00-03:00').meeting
    Crm::Meetings::CancelService.new(meeting: meeting).perform
    book(starts_at: '2026-10-20T11:00:00-03:00')

    expect(book(starts_at: '2026-10-21T11:00:00-03:00').meeting).to be_persisted
  end

  it 'liga o card à conversa do mesmo cliente' do
    contact = account.contacts.create!(name: 'Ana', phone_number: '+5521988887777')
    conversation = create_crm_conversation(account: account, inbox: create_crm_inbox(account: account), contact: contact)

    card = book(conversation: conversation, source: 'invite').card

    expect(card).to have_attributes(conversation_id: conversation.id, source: 'invite', owner_id: world.host.id)
  end

  it 'segue confirmado quando o aviso em tempo real falha' do
    allow(Crm::Cards::Broadcaster).to receive(:broadcast).and_raise(StandardError, 'cable down')

    expect(book.meeting).to be_persisted
  end

  it 'falha fechada quando o provedor da caixa não responde' do
    inbox = create(:channel_email, account: account, provider: 'google', calendar_enabled: true).inbox
    profile.update!(inbox: inbox)
    allow(Google::FreeBusyService).to receive(:new).and_raise(Google::FreeBusyService::Error, 'boom')

    with_modified_env(CRM_CALENDAR_GOOGLE_SIMULATE: 'false') do
      expect { book }.to raise_error(ArgumentError, 'availability_unavailable')
    end
    expect(account.crm_meetings.count).to eq(0)
  end

  it 'agenda Google Meet pelo Creator quando a página oferece esse local' do
    inbox = create(:channel_email, account: account, provider: 'google', calendar_enabled: true).inbox
    profile.update!(inbox: inbox, locations: [{ 'type' => 'google_meet' }])

    meeting = with_modified_env(CRM_CALENDAR_GOOGLE_SIMULATE: 'true') { book(email: 'ana@example.com').meeting }

    expect(meeting).to have_attributes(provider: 'google', online_meeting_type: 'google_meet', source: 'public_link', inbox_id: inbox.id)
    expect(meeting.metadata).to include('booking_profile_id' => profile.id)
  end
end
