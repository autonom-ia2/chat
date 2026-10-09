require 'rails_helper'

# Horários com as regras de equipe (#1195): feriados nacionais (J3-A13) e "Meus horários" (J8-A11).
RSpec.describe Crm::BookingV2::Slots do
  let(:account) { create(:account) }
  let(:world) { build_booking_world(account: account) }
  let(:profile) { world.profile }

  # Segunda-feira, 12/10/2026, 08:00 em São Paulo: Nossa Senhora Aparecida, feriado nacional.
  before { travel_to Time.utc(2026, 10, 12, 11, 0, 0) }

  def slots(date)
    described_class.new(profile: profile, host: world.host, date: date).perform
  end

  def availability(**attrs)
    Crm::AgentAvailability.create!({ account: account, user: world.host }.merge(attrs))
  end

  describe 'feriados nacionais' do
    it 'página nova nasce fechando feriados' do
      page = account.crm_agent_booking_profiles.create!(page_version: Crm::AgentBookingProfile::NEW_PAGE, enabled: false)

      expect(page.close_holidays).to be(true)
    end

    it 'não oferece horário no feriado quando ligado, e oferece no dia seguinte' do
      profile.update!(close_holidays: true)

      expect(slots('2026-10-12')).to eq([])
      expect(slots('2026-10-13').first).to eq('2026-10-13T09:00:00-03:00')
    end

    it 'oferece o feriado quando o admin desliga a opção' do
      profile.update!(close_holidays: false)

      expect(slots('2026-10-12').first).to eq('2026-10-12T09:00:00-03:00')
    end

    it 'fecha feriado móvel (Corpus Christi de 2027) e fixo (Finados de 2026)' do
      profile.update!(close_holidays: true, booking_window_days: 90)

      expect(slots('2026-11-02')).to eq([])
      expect(slots('2026-11-03')).not_to be_empty
      travel_to Time.utc(2027, 5, 20, 11, 0, 0)
      expect(slots('2027-05-27')).to eq([])
      expect(slots('2027-05-28')).not_to be_empty
    end

    it 'o próximo horário pula o feriado' do
      profile.update!(close_holidays: true)

      expect(described_class.next_slot(profile: profile, host: world.host)).to eq('2026-10-13T09:00:00-03:00')
    end

    it 'usa a data no fuso da página: 12/10 em Tóquio fecha mesmo sendo 11/10 em São Paulo' do
      travel_to Time.utc(2026, 10, 10, 11, 0, 0)
      profile.update!(close_holidays: true, timezone: 'Asia/Tokyo', working_hours: { 'start_hour' => 0, 'end_hour' => 24, 'weekdays' => [0, 1] })

      expect(slots('2026-10-12')).to eq([])
      expect(slots('2026-10-11').first).to eq('2026-10-11T00:00:00+09:00')
    end
  end

  describe 'Meus horários' do
    let(:tuesday) { '2026-10-13' }

    it 'sem ajuste próprio, segue a página' do
      expect(slots(tuesday).first).to eq('2026-10-13T09:00:00-03:00')
      expect(slots(tuesday).last).to eq('2026-10-13T16:30:00-03:00')
    end

    it 'usa só a interseção dos dias e horas da pessoa com os da página' do
      availability(working_hours: { 'start_hour' => 10, 'end_hour' => 12, 'weekdays' => [2, 3] })

      expect(slots(tuesday)).to eq(%w[2026-10-13T10:00:00-03:00 2026-10-13T10:30:00-03:00
                                      2026-10-13T11:00:00-03:00 2026-10-13T11:30:00-03:00])
      expect(slots('2026-10-15')).to eq([]) # quinta: a pessoa não atende
    end

    it 'nunca amplia a página: horas e dias de fora são cortados' do
      Crm::AgentAvailability.new(account: account, user: world.host,
                                 working_hours: { 'start_hour' => 6, 'end_hour' => 22, 'weekdays' => [0, 2, 6] }).save!

      expect(slots(tuesday).first).to eq('2026-10-13T09:00:00-03:00')
      expect(slots(tuesday).last).to eq('2026-10-13T16:30:00-03:00')
      expect(slots('2026-10-17')).to eq([]) # sábado: a página não abre
      expect(slots('2026-10-18')).to eq([]) # domingo: idem
    end

    it 'sem sobra na interseção, não oferece nada' do
      availability(working_hours: { 'start_hour' => 18, 'end_hour' => 20, 'weekdays' => [2] })

      expect(slots(tuesday)).to eq([])
    end

    it 'agenda pausada não oferece horário nem próximo horário' do
      availability(paused: true)

      expect(slots(tuesday)).to eq([])
      expect(described_class.next_slot(profile: profile, host: world.host)).to be_nil
    end

    it 'o ajuste de outra pessoa não muda a página de quem atende' do
      other = create(:user, account: account, role: :agent)
      Crm::AgentAvailability.create!(account: account, user: other, paused: true)

      expect(slots(tuesday).size).to eq(16)
    end

    it 'a reserva recusa horário fora dos horários da pessoa' do
      availability(working_hours: { 'start_hour' => 14, 'end_hour' => 17, 'weekdays' => [2] })

      booker = Crm::BookingV2::Booker.new(profile: profile, name: 'Ana', phone: '+5521988887777',
                                          starts_at: '2026-10-13T10:00:00-03:00', source: 'public_link')

      expect { booker.perform }.to raise_error(ArgumentError, 'slot_unavailable')
      expect(Crm::Meeting.where(account_id: account.id).count).to eq(0)
    end
  end
end
