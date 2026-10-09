require 'rails_helper'

RSpec.describe Crm::BookingV2::Slots do
  let(:account) { create(:account) }
  let(:world) { build_booking_world(account: account) }
  let(:profile) { world.profile }
  let(:monday) { '2026-10-12' }
  let(:sao_paulo) { ActiveSupport::TimeZone['America/Sao_Paulo'] }

  # Segunda-feira, 08:00 em São Paulo (11:00 UTC; o servidor de teste roda em UTC).
  before { travel_to Time.utc(2026, 10, 12, 11, 0, 0) }

  def slots(date: monday, **)
    described_class.new(profile: profile, host: world.host, date: date, **).perform
  end

  def local(day, hour, minute = 0)
    sao_paulo.parse("#{day} #{hour.to_s.rjust(2, '0')}:#{minute.to_s.rjust(2, '0')}")
  end

  it 'lista os inícios do dia no horário de trabalho, no fuso do perfil, com offset' do
    result = slots

    expect(result.first).to eq('2026-10-12T09:00:00-03:00')
    expect(result.last).to eq('2026-10-12T16:30:00-03:00')
    expect(result.size).to eq(16)
  end

  it 'usa o fuso do perfil mesmo quando ele difere do servidor' do
    profile.update!(timezone: 'Asia/Tokyo')

    result = slots(date: '2026-10-13')

    expect(result.first).to eq('2026-10-13T09:00:00+09:00')
    expect(Time.iso8601(result.first).utc).to eq(Time.utc(2026, 10, 13, 0, 0, 0))
  end

  it 'respeita a antecedência mínima' do
    profile.update!(min_notice_minutes: 120)

    expect(slots.first).to eq('2026-10-12T10:00:00-03:00')
  end

  it 'aplica o intervalo antes e depois das reuniões do responsável' do
    profile.update!(buffer_minutes: 15)
    create_internal_meeting(world: world, starts_at: local(monday, 10))

    result = slots

    expect(result).to include('2026-10-12T09:00:00-03:00', '2026-10-12T11:00:00-03:00')
    expect(result).not_to include('2026-10-12T09:30:00-03:00', '2026-10-12T10:00:00-03:00', '2026-10-12T10:30:00-03:00')
  end

  it 'considera reuniões do responsável em qualquer caixa e ignora as de outra pessoa' do
    world.contact.update!(email: 'marcos@example.com')
    inbox = create(:channel_email, account: account, provider: 'google', calendar_enabled: true).inbox
    google = { provider: :google, online_meeting_type: :google_meet, inbox: inbox, external_event_id: 'sim-1' }
    create_internal_meeting(world: world, starts_at: local(monday, 14), **google)
    other = create(:user, account: account, role: :agent)
    create_internal_meeting(world: world, starts_at: local(monday, 15), created_by: other)
    create_internal_meeting(world: world, starts_at: local(monday, 16), status: :canceled)

    result = slots

    expect(result).not_to include('2026-10-12T14:00:00-03:00')
    expect(result).to include('2026-10-12T15:00:00-03:00', '2026-10-12T16:00:00-03:00')
  end

  it 'devolve vazio fora dos dias de trabalho, antes de hoje, depois da janela e com data inválida' do
    expect(slots(date: '2026-10-17')).to eq([])
    expect(slots(date: '2026-10-09')).to eq([])
    expect(slots(date: '2026-10-30')).to eq([])
    expect(slots(date: 'ontem')).to eq([])
  end

  it 'aceita só durações da página' do
    profile.update!(slot_durations: [60])

    expect(slots(duration: 60).first(2)).to eq(%w[2026-10-12T09:00:00-03:00 2026-10-12T10:00:00-03:00])
    expect(slots(duration: '30').size).to eq(16)
    expect { slots(duration: 45) }.to raise_error(ArgumentError, 'invalid_duration')
    expect { slots(duration: 'meia hora') }.to raise_error(ArgumentError, 'invalid_duration')
  end

  context 'with caixa de calendário Google' do
    let(:inbox) { create(:channel_email, account: account, provider: 'google', calendar_enabled: true).inbox }
    let(:free_busy) { instance_double(Google::FreeBusyService) }

    before do
      profile.update!(inbox: inbox)
      allow(Google::FreeBusyService).to receive(:new).and_return(free_busy)
    end

    it 'tira os horários ocupados no provedor' do
      allow(free_busy).to receive(:busy_intervals).and_return([{ start: local(monday, 13), end: local(monday, 14) }])

      with_modified_env(CRM_CALENDAR_GOOGLE_SIMULATE: 'false') do
        expect(slots).not_to include('2026-10-12T13:00:00-03:00', '2026-10-12T13:30:00-03:00')
        expect(slots).to include('2026-10-12T14:00:00-03:00')
      end
    end

    it 'falha fechada no modo estrito e mostra só a ocupação local fora dele' do
      allow(free_busy).to receive(:busy_intervals).and_raise(Google::FreeBusyService::Error, 'Google free/busy returned 500')

      with_modified_env(CRM_CALENDAR_GOOGLE_SIMULATE: 'false') do
        expect { slots(strict: true) }.to raise_error(ArgumentError, 'availability_unavailable')
        expect(slots.size).to eq(16)
      end
      expect(free_busy).to have_received(:busy_intervals).with(raise_on_error: true).once
    end

    it 'não chama o provedor em simulação' do
      with_modified_env(CRM_CALENDAR_GOOGLE_SIMULATE: 'true') { expect(slots.size).to eq(16) }

      expect(Google::FreeBusyService).not_to have_received(:new)
    end
  end

  describe '.next_slot' do
    it 'acha o próximo horário livre pulando o fim de semana' do
      travel_to Time.utc(2026, 10, 16, 21, 0, 0)

      expect(described_class.next_slot(profile: profile, host: world.host)).to eq('2026-10-19T09:00:00-03:00')
    end

    it 'pula horários ocupados e respeita o `from`' do
      create_internal_meeting(world: world, starts_at: local(monday, 9))

      expect(described_class.next_slot(profile: profile, host: world.host)).to eq('2026-10-12T09:30:00-03:00')
      expect(described_class.next_slot(profile: profile, host: world.host, from: local('2026-10-14', 12))).to eq('2026-10-14T12:00:00-03:00')
    end

    it 'devolve nil quando nada cabe na janela' do
      profile.update!(booking_window_days: 1, working_hours: { 'start_hour' => 9, 'end_hour' => 17, 'weekdays' => [3] })

      expect(described_class.next_slot(profile: profile, host: world.host)).to be_nil
    end

    it 'faz uma consulta só ao provedor para todos os dias e reaproveita o cache' do
      inbox = create(:channel_email, account: account, provider: 'google', calendar_enabled: true).inbox
      profile.update!(inbox: inbox)
      free_busy = instance_double(Google::FreeBusyService, busy_intervals: [{ start: local(monday, 9), end: local(monday, 17) }])
      allow(Google::FreeBusyService).to receive(:new).and_return(free_busy)
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)

      with_modified_env(CRM_CALENDAR_GOOGLE_SIMULATE: 'false') do
        2.times { expect(described_class.next_slot(profile: profile, host: world.host)).to eq('2026-10-13T09:00:00-03:00') }
      end

      expect(Google::FreeBusyService).to have_received(:new)
        .with(channel: inbox.channel, time_min: local(monday, 9), time_max: local('2026-10-26', 17)).once
    end
  end
end
