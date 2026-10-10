require 'rails_helper'

# Números do painel de resultados (#1194): J7-A1 (cinco números do período), J7-A2 (eventos registrados, batendo com
# o card, sem dado pessoal, sem teste), J7-A3 (origem), J8-A12 ("meus" x equipe), RA-19 (confirmou).
RSpec.describe Crm::BookingV2::Results do
  let(:account) { create(:account, reporting_timezone: 'America/Sao_Paulo') }
  let(:world) { build_booking_world(account: account) }
  let(:other_host) { create(:user, account: account, role: :agent, name: 'Rui Prado') }
  # Sexta, 9/10/2026, 15h em São Paulo.
  let(:now) { Time.zone.parse('2026-10-09 18:00:00 UTC') }

  around { |example| travel_to(now) { example.run } }

  def period(days = 7)
    Crm::BookingV2::ResultsPeriod.new(account: account, days: days)
  end

  def results(days: 7, user: nil)
    described_class.new(account: account, period: period(days), user: user)
  end

  def invite(**attrs)
    create_booking_invite(world: world, channel: 'conversation', **attrs)
  end

  def meeting(source:, created_at: 1.day.ago, created_by: world.host, card: world.card, **attrs)
    create_internal_meeting(world: world, starts_at: 3.days.from_now, source: source, created_by: created_by, card: card, **attrs)
      .tap { |record| record.update_columns(created_at: created_at) } # rubocop:disable Rails/SkipsModelValidations
  end

  # Reunião que já aconteceu, com o resultado gravado pelo mesmo serviço do card (atividade no card).
  def finished(source:, outcome:, recorded_at: 1.hour.ago, **attrs)
    record = create_internal_meeting(world: world, starts_at: recorded_at - 1.day, source: source, **attrs)
    travel_to(recorded_at)
    Crm::Meetings::RecordOutcomeService.new(meeting: record, outcome: outcome).perform
    travel_to(now)
    record
  end

  describe 'period' do
    it 'starts at the beginning of the first day in the account time zone, counting today' do
      expect(period(7).since).to eq(Time.find_zone('America/Sao_Paulo').parse('2026-10-03 00:00'))
      expect(period(30).since).to eq(Time.find_zone('America/Sao_Paulo').parse('2026-09-10 00:00'))
      expect(period(nil).days).to eq(30)
    end

    it 'refuses any other window' do
      %w[1 14 abc 7.0].each do |value|
        expect { period(value) }.to raise_error(Crm::BookingV2::InviteError, 'invalid_period')
      end
    end
  end

  describe '#totals' do
    it 'counts each registered event in the period and nothing else (J7-A1, J7-A2, RA-19)' do
      invite(sent_at: 2.days.ago)
      invite(sent_at: 3.days.ago, first_opened_at: 2.days.ago)
      invite(sent_at: 10.days.ago, first_opened_at: 1.day.ago) # enviado fora, aberto dentro do período de 7 dias
      invite(sent_at: 20.days.ago)
      # Aberto só depois de marcar (link de gestão): não conta como "abriu".
      booked_meeting = meeting(source: 'invite')
      invite(sent_at: 2.days.ago, scheduled_at: 1.day.ago, first_opened_at: 1.hour.ago, meeting: booked_meeting)
      meeting(source: 'public_link', confirmed_at: 1.hour.ago, confirmation_status: :confirmed)
      meeting(source: 'invite', created_at: 9.days.ago)
      meeting(source: nil) # reunião marcada à mão no CRM, fora do agendamento novo
      finished(source: 'invite', outcome: 'held')
      finished(source: 'public_link', outcome: 'held')
      finished(source: 'invite', outcome: 'no_show')
      finished(source: 'invite', outcome: 'no_show', recorded_at: 8.days.ago)
      finished(source: nil, outcome: 'no_show')

      expect(results.totals).to eq(sent: 3, opened: 2, booked: 2 + 4, confirmed: 1, attended: 2, no_show: 1)
      expect(results(days: 30).totals).to include(sent: 5, opened: 2, booked: 3 + 4, no_show: 2)
    end

    it 'leaves test invites and the meetings they created out (J3-A11)' do
      test_meeting = meeting(source: 'invite')
      invite(sent_at: 1.day.ago, first_opened_at: 1.hour.ago, scheduled_at: 1.hour.ago, meeting: test_meeting,
             metadata: { 'test' => true })
      invite(sent_at: 1.day.ago, first_opened_at: 1.hour.ago, metadata: { 'test' => true })

      expect(results.totals).to eq(sent: 0, opened: 0, booked: 0, confirmed: 0, attended: 0, no_show: 0)
    end

    it 'does not count public-link invites as sent or opened: they are born already booked' do
      public_meeting = meeting(source: 'public_link')
      invite(channel: 'public', sent_at: 1.day.ago, first_opened_at: 1.hour.ago, scheduled_at: 1.day.ago, meeting: public_meeting)

      expect(results.totals).to include(sent: 0, opened: 0, booked: 1)
    end

    it 'matches what the cards show: invite states and the outcome activity of each meeting' do
      sent = invite(sent_at: 1.day.ago)
      opened = invite(sent_at: 1.day.ago, first_opened_at: 1.hour.ago)
      held = finished(source: 'invite', outcome: 'held')
      missed = finished(source: 'invite', outcome: 'no_show')

      states = [sent, opened].map { |record| Crm::BookingV2::InviteSerializer.new(record).as_json[:state] }
      outcomes = Crm::Activity.where(event_type: 'meeting_outcome_recorded', card_id: world.card.id).map { |row| row.payload['outcome'] }
      totals = results.totals

      expect(states).to eq(%w[sent opened])
      expect(totals[:sent]).to eq(2)
      expect(totals[:opened]).to eq(states.count('opened'))
      expect([totals[:attended], totals[:no_show]]).to eq([outcomes.count('held'), outcomes.count('no_show')])
      expect([held.reload.outcome, missed.reload.outcome]).to eq(%w[held no_show])
    end

    it 'gives only counts: no name, phone or id of a client (J7-A2)' do
      invite(sent_at: 1.day.ago, first_opened_at: 1.hour.ago)
      meeting(source: 'invite')
      json = { totals: results.totals, origins: results.origins }.to_json

      expect(json).not_to include(world.contact.name, world.contact.phone_number)
      expect(results.totals.values).to all(be_a(Integer))
    end
  end

  describe '"Meus números" (J8-A12)' do
    it 'counts the links the person created and the meetings the person hosts' do
      invite(sent_at: 1.day.ago, first_opened_at: 1.hour.ago)
      invite(sent_at: 1.day.ago, created_by: other_host)
      meeting(source: 'invite')
      meeting(source: 'public_link', created_by: other_host)
      finished(source: 'invite', outcome: 'held', created_by: other_host)

      expect(results(user: world.host).totals).to eq(sent: 1, opened: 1, booked: 1, confirmed: 0, attended: 0, no_show: 0)
      expect(results(user: other_host).totals).to eq(sent: 1, opened: 0, booked: 1 + 1, confirmed: 0, attended: 1, no_show: 0)
      expect(results.totals).to include(sent: 2, booked: 3, attended: 1)
    end
  end

  describe '#origins (J7-A3)' do
    it 'splits the booked meetings into conversation, public link and contact request, adding AI only when there is one' do
      request_card = create_booking_card(account: account, pipeline: world.pipeline, stage: world.stage, contact: world.contact,
                                         source: 'contact_request')
      meeting(source: 'invite')
      meeting(source: 'invite')
      meeting(source: 'public_link')
      meeting(source: 'public_link', card: request_card)
      meeting(source: 'invite', created_at: 20.days.ago)

      expect(results.origins).to eq([
                                      { key: 'conversation', count: 2 }, { key: 'public_link', count: 1 },
                                      { key: 'contact_request', count: 1 }
                                    ])
      expect(results.origins.sum { |row| row[:count] }).to eq(results.totals[:booked])

      meeting(source: 'ai')
      expect(results.origins.last).to eq(key: 'ai', count: 1)
    end
  end
end
