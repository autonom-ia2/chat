require 'rails_helper'

# Trava de agente no v1 (#1188): o link antigo também toma o lock do responsável e enxerga as reuniões internas dele.
RSpec.describe Crm::Calendar::PublicBookingService do
  let(:account) { create(:account) }
  let(:world) { build_booking_world(account: account) }
  let(:inbox) { create(:channel_email, account: account, provider: 'google', calendar_enabled: true).inbox }
  let(:legacy_profile) do
    create_booking_profile(account: account, host: world.host, pipeline: world.pipeline, stage: world.stage,
                           page_version: Crm::AgentBookingProfile::LEGACY_PAGE, inbox: inbox, locations: [])
  end
  let(:slot) { '2026-10-20T10:00:00-03:00' }

  before { travel_to Time.utc(2026, 10, 12, 11, 0, 0) }

  def confirm(starts_at: slot)
    described_class.new(profile: legacy_profile, name: 'Ana', email: 'ana@example.com', starts_at: starts_at).confirm_booking!
  end

  it 'toma o lock da caixa e depois o do agente' do
    statements = []
    connection = ActiveRecord::Base.connection
    allow(connection).to receive(:execute).and_wrap_original do |original, sql, *args|
      statements << sql if sql.to_s.include?('pg_advisory_xact_lock')
      original.call(sql, *args)
    end

    expect(confirm.confirmed).to be(true)
    expect(statements).to eq(["SELECT pg_advisory_xact_lock(1, #{inbox.id})", "SELECT pg_advisory_xact_lock(2, #{world.host.id})"])
  end

  it 'recusa horário ocupado por reunião interna do mesmo responsável e libera o de outra pessoa' do
    create_internal_meeting(world: world, starts_at: Time.iso8601(slot))
    other = create(:user, account: account, role: :agent)
    create_internal_meeting(world: world, starts_at: Time.iso8601('2026-10-20T11:00:00-03:00'), created_by: other)

    expect { confirm }.to raise_error(ArgumentError, 'slot_unavailable')
    expect(confirm(starts_at: '2026-10-20T11:00:00-03:00').confirmed).to be(true)
  end

  it 'esconde da página antiga o horário da reunião interna do responsável' do
    create_internal_meeting(world: world, starts_at: Time.iso8601(slot))

    slots = Crm::Calendar::PublicAvailableSlots.new(profile: legacy_profile, date: '2026-10-20').perform

    expect(slots).not_to include(slot)
    expect(slots).to include('2026-10-20T09:00:00-03:00', '2026-10-20T10:30:00-03:00')
  end
end
