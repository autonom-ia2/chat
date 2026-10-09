require 'rails_helper'

RSpec.describe 'Autonomia::Agents::ListStats', type: :service do
  let(:account) { create(:account) }
  let(:service_class) { Autonomia::Agents::ListStats }
  let(:clara) do
    Autonomia::Agents::Agent.create!(
      account: account, name: 'Clara', agent_type: 'custom', status: :active, enabled: true,
      instruction: 'Atenda o cliente.'
    )
  end
  let(:lia) do
    Autonomia::Agents::Agent.create!(
      account: account, name: 'Lia', agent_type: 'custom', status: :active, enabled: true,
      instruction: 'Atenda o cliente.'
    )
  end
  let(:other_agent) do
    Autonomia::Agents::Agent.create!(
      account: account, name: 'Outro agente', agent_type: 'custom', status: :active, enabled: true,
      instruction: 'Atenda o cliente.'
    )
  end
  let(:now) { Time.zone.local(2024, 10, 7, 15, 30, 0) }

  around do |example|
    travel_to(now) { example.run }
  end

  def create_event(agent, event_type, at:)
    Autonomia::Agents::AgentEvent.create!(
      account: account, agent: agent, event_type: event_type, created_at: at
    )
  end

  def analytics_counts(agent, range)
    payload = Autonomia::Agents::Analytics.new(agent: agent, range: range).call
    { replies: payload[:replies_sent], handoffs: payload[:handoff_count] }
  end

  before do
    create_event(clara, :replied, at: now - 2.days)
    create_event(clara, :replied, at: now - 8.days)
    create_event(clara, :handed_off, at: now - 3.days)
    create_event(clara, :skipped_audience, at: now - 10.days)
    create_event(clara, :skipped_schedule, at: now - 20.days)
    create_event(clara, :skipped_escolhas_incompletas, at: now - 1.day)
    create_event(clara, :replied, at: now - 30.days + 1.hour)

    create_event(lia, :replied, at: now - 1.day)
    create_event(lia, :replied, at: now - 29.days + 1.hour)
    create_event(lia, :skipped_schedule, at: now - 5.days)
    create_event(lia, :handed_off, at: now - 20.days)
    create_event(lia, :skipped_escolhas_incompletas, at: now - 2.days)
    create_event(lia, :replied, at: now + 1.hour)

    create_event(other_agent, :replied, at: now - 1.day)
  end

  it 'returns both windows per agent with the same counts as Analytics and HANDOFF_TYPES' do
    stats = service_class.new(agents: [clara, lia], now: now).call

    expect(stats.keys).to contain_exactly(clara.id, lia.id)
    expect(stats[clara.id]).to eq(
      week: analytics_counts(clara, '7d'), month: analytics_counts(clara, '30d')
    )
    expect(stats[lia.id]).to eq(
      week: analytics_counts(lia, '7d'), month: analytics_counts(lia, '30d')
    )

    expect(stats[clara.id][:week]).to eq(replies: 1, handoffs: 1)
    expect(stats[clara.id][:month]).to eq(replies: 2, handoffs: 3)
    expect(stats[lia.id][:week]).to eq(replies: 1, handoffs: 1)
    expect(stats[lia.id][:month]).to eq(replies: 2, handoffs: 2)
  end

  it 'uses one batch aggregate query for all requested agents and both windows' do
    event_queries = []
    subscriber = lambda do |_name, _start, _finish, _id, payload|
      sql = payload[:sql].to_s
      event_queries << sql if sql.downcase.include?('autonomia_agent_events')
    end

    stats = ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
      service_class.new(agents: [clara, lia], now: now).call
    end

    expect(stats.keys).to contain_exactly(clara.id, lia.id)
    expect(event_queries.size).to eq(1)
    expect(event_queries.first.upcase).to include('GROUP BY')
  end
end
