require 'rails_helper'

# "Passar reuniões" (#1195, J8-A10): prévia sem gravar, passagem só das livres, conflitos devolvidos sem mexer,
# filtro por página, pessoa nova precisa poder atender, lembrete e atividade no card.
RSpec.describe Crm::BookingV2::Reassigner do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator, name: 'Admin') }
  let(:world) { build_booking_world(account: account) }
  let(:from) { world.host }
  let(:to) { create(:user, account: account, role: :agent, name: 'Rui Prado') }
  let(:other_page) { create_booking_profile(account: account, host: from, pipeline: world.pipeline, stage: world.stage) }
  let(:tuesday) { ActiveSupport::TimeZone['America/Sao_Paulo'].parse('2026-10-20 10:00') }

  before { travel_to Time.utc(2026, 10, 12, 11, 0, 0) }

  def page_meeting(host, starts_at, profile: world.profile, **attrs)
    create_internal_meeting(world: world, starts_at: starts_at, created_by: host, metadata: { 'booking_profile_id' => profile.id }, **attrs)
  end

  def reassigner(page: nil, to_user: to, from_user: from)
    described_class.new(account: account, from_user_id: from_user.id, to_user_id: to_user&.id, page: page, actor: admin)
  end

  def as_payload(result)
    JSON.parse(result.to_json)
  end

  describe '#preview' do
    it 'mostra quantas passam e os conflitos sem gravar nada' do
      free = page_meeting(from, tuesday)
      busy = page_meeting(from, tuesday + 1.hour)
      page_meeting(to, tuesday + 1.hour + 15.minutes)

      result = nil
      expect { result = reassigner.preview }.not_to(change { [Crm::Meeting.order(:id).pluck(:created_by_id), Crm::Activity.count] })

      expect(as_payload(result)).to eq(
        'moved' => 1,
        'conflicts' => [{ 'meeting_id' => busy.id, 'starts_at' => busy.starts_at.iso8601, 'title' => busy.title }]
      )
      expect(free.reload.created_by_id).to eq(from.id)
    end
  end

  describe '#perform' do
    it 'passa as livres, devolve os conflitos sem mexer neles e registra a atividade no card' do
      free = page_meeting(from, tuesday)
      busy = page_meeting(from, tuesday + 1.hour)
      blocker = page_meeting(to, tuesday + 1.hour + 15.minutes)

      result = as_payload(reassigner.perform)

      expect(result['moved']).to eq(1)
      expect(result['conflicts'].map { |row| row['meeting_id'] }).to eq([busy.id])
      expect(free.reload.created_by_id).to eq(to.id)
      expect(busy.reload.created_by_id).to eq(from.id)
      expect(blocker.reload.created_by_id).to eq(to.id)
      activity = Crm::Activity.find_by!(account: account, event_type: 'meeting_host_reassigned')
      expect(activity).to have_attributes(card_id: world.card.id, actor_type: 'user', actor_id: admin.id)
      expect(activity.payload).to eq(
        'meeting_id' => free.id, 'from_user_id' => from.id, 'to_user_id' => to.id,
        'booking_profile_id' => world.profile.id, 'reason' => 'manual'
      )
    end

    it 'duas reuniões no mesmo horário nunca vão para a mesma pessoa' do
      first = page_meeting(from, tuesday)
      second = page_meeting(from, tuesday, profile: other_page)

      result = as_payload(reassigner.perform)

      expect(result['moved']).to eq(1)
      expect(result['conflicts'].map { |row| row['meeting_id'] }).to eq([second.id])
      expect(first.reload.created_by_id).to eq(to.id)
      expect(second.reload.created_by_id).to eq(from.id)
      expect(Crm::Meeting.where(created_by_id: to.id, starts_at: tuesday, status: :scheduled).count).to eq(1)
    end

    it 'respeita o intervalo da página ao conferir o horário da pessoa nova' do
      world.profile.update!(buffer_minutes: 30)
      meeting = page_meeting(from, tuesday)
      page_meeting(to, tuesday + 45.minutes)

      result = as_payload(reassigner.perform)

      expect(result).to include('moved' => 0)
      expect(meeting.reload.created_by_id).to eq(from.id)
    end

    it 'ignora reuniões canceladas e passadas da pessoa nova e da antiga' do
      page_meeting(to, tuesday, status: :canceled)
      past = page_meeting(from, 2.days.ago)
      meeting = page_meeting(from, tuesday)

      expect(as_payload(reassigner.perform)).to eq('moved' => 1, 'conflicts' => [])
      expect(meeting.reload.created_by_id).to eq(to.id)
      expect(past.reload.created_by_id).to eq(from.id)
    end

    it 'com página escolhida, passa só as reuniões dela' do
      mine = page_meeting(from, tuesday)
      other = page_meeting(from, tuesday + 2.hours, profile: other_page)

      expect(as_payload(reassigner(page: world.profile).perform)).to eq('moved' => 1, 'conflicts' => [])

      expect(mine.reload.created_by_id).to eq(to.id)
      expect(other.reload.created_by_id).to eq(from.id)
    end

    it 'sem página, passa as de todas as páginas novas e deixa as que não vieram de página' do
      mine = page_meeting(from, tuesday)
      other = page_meeting(from, tuesday + 2.hours, profile: other_page)
      manual = create_internal_meeting(world: world, starts_at: tuesday + 4.hours, created_by: from)

      expect(as_payload(reassigner.perform)['moved']).to eq(2)

      expect([mine, other].map { |meeting| meeting.reload.created_by_id }).to eq([to.id, to.id])
      expect(manual.reload.created_by_id).to eq(from.id)
    end

    it 'passa junto o lembrete pendente que estava com a pessoa antiga' do
      meeting = page_meeting(from, tuesday)
      reminder = Crm::FollowUp.create!(account: account, card: world.card, contact: world.contact, assignee: from, created_by: from,
                                       title: 'Lembrete', due_at: tuesday - 15.minutes, follow_up_type: :meeting, status: :pending)
      meeting.update!(reminder: reminder)

      reassigner.perform

      expect(reminder.reload.assignee_id).to eq(to.id)
    end

    it 'recusa pessoa nova que não pode atender, a mesma pessoa e pessoa de fora da conta, sem mexer em nada' do
      meeting = page_meeting(from, tuesday)
      no_crm = create(:user, account: account, role: :agent)
      role = create(:custom_role, account: account, permissions: ['agendamento_manage'])
      no_crm.account_users.find_by(account: account).update!(custom_role: role)
      outsider = create(:user)

      [no_crm, from, outsider, nil].each do |target|
        expect { reassigner(to_user: target).perform }.to raise_error(described_class::InvalidPeople)
      end
      expect(meeting.reload.created_by_id).to eq(from.id)
      expect(Crm::Activity.where(event_type: 'meeting_host_reassigned')).to be_empty
    end
  end
end
