require 'rails_helper'

# #284 (Entrega 2a) — porta única "o agente deve atender?": público-alvo + horário de atuação.
RSpec.describe Autonomia::Agents::Operate::EngagementGate do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, timezone: 'America/Sao_Paulo') }
  let(:contact) { create(:contact, account: account, additional_attributes: { 'country_code' => 'BR' }) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  # Quarta-feira, 10:00 e 21:00 em America/Sao_Paulo.
  let(:open_time)   { Time.zone.parse('2026-09-02 10:00 -03:00') }
  let(:closed_time) { Time.zone.parse('2026-09-02 21:00 -03:00') }

  def agent_with(config)
    Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.', config: config)
  end

  def reason_for(config)
    described_class.new(agent: agent_with(config), conversation: conversation).blocked_reason
  end

  it 'lets everything through when nothing is configured' do
    expect(reason_for({})).to be_nil
    expect(reason_for('audience' => nil, 'response_window' => 'always')).to be_nil
  end

  describe 'audience' do
    let(:brazil) { { 'attribute_key' => 'country_code', 'filter_operator' => 'equal_to', 'values' => ['BR'] } }
    let(:usa) { { 'attribute_key' => 'country_code', 'filter_operator' => 'equal_to', 'values' => ['US'] } }

    it 'passes contacts inside the audience and blocks the others' do
      expect(reason_for('audience' => brazil)).to be_nil
      expect(reason_for('audience' => usa)).to eq('audience')
    end
  end

  describe 'response window with a Crm::ServiceSchedule on the inbox' do
    before { create(:crm_service_schedule, account: account, owner: inbox, weekdays: [1, 2, 3, 4, 5], hours: [['09:00', '18:00']]) }

    it 'follows the schedule for business_hours' do
      travel_to(open_time) { expect(reason_for('response_window' => 'business_hours')).to be_nil }
      travel_to(closed_time) { expect(reason_for('response_window' => 'business_hours')).to eq('schedule') }
    end

    it 'inverts it for outside_business_hours' do
      travel_to(open_time) { expect(reason_for('response_window' => 'outside_business_hours')).to eq('schedule') }
      travel_to(closed_time) { expect(reason_for('response_window' => 'outside_business_hours')).to be_nil }
    end

    it 'prefers the service schedule over the inbox working hours' do
      inbox.update!(working_hours_enabled: true)
      allow(conversation.inbox).to receive(:out_of_office?).and_return(true)

      travel_to(open_time) { expect(reason_for('response_window' => 'business_hours')).to be_nil }
    end
  end

  describe 'response window with inbox working hours only' do
    before { inbox.update!(working_hours_enabled: true) }

    it 'uses the inbox out_of_office? state' do
      allow(conversation.inbox).to receive(:out_of_office?).and_return(true)
      expect(reason_for('response_window' => 'business_hours')).to eq('schedule')
      expect(reason_for('response_window' => 'outside_business_hours')).to be_nil

      allow(conversation.inbox).to receive(:out_of_office?).and_return(false)
      expect(reason_for('response_window' => 'business_hours')).to be_nil
    end
  end

  it 'treats an inbox without any schedule source as always open' do
    expect(reason_for('response_window' => 'business_hours')).to be_nil
    expect(reason_for('response_window' => 'outside_business_hours')).to be_nil
  end

  it 'reports the audience before the schedule when both block' do
    usa = { 'attribute_key' => 'country_code', 'filter_operator' => 'equal_to', 'values' => ['US'] }
    inbox.update!(working_hours_enabled: true)
    allow(conversation.inbox).to receive(:out_of_office?).and_return(true)

    expect(reason_for('audience' => usa, 'response_window' => 'business_hours')).to eq('audience')
  end
end
