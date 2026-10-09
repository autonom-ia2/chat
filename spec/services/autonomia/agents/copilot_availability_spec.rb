require 'rails_helper'

RSpec.describe 'Autonomia::Agents::CopilotAvailability' do
  let(:account) { create(:account) }
  let(:service_class) { Autonomia::Agents::CopilotAvailability }

  def result_for(flags)
    allow(Crm::Config).to receive(:enabled?).and_return(flags[:crm_enabled])
    allow(Autonomia::Agents::Config).to receive(:enabled?).with(account).and_return(flags[:autonomia_enabled])
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(flags[:crm_ai_enabled])

    with_modified_env CRM_COPILOT_ENABLED: flags[:copilot_env].to_s do
      service_class.new(account: account).call
    end
  end

  gate_names = %i[crm_enabled autonomia_enabled copilot_env crm_ai_enabled]

  (0...(2**gate_names.length)).each do |mask|
    flags = gate_names.each_with_index.to_h { |flag, index| [flag, mask.anybits?(1 << index)] }
    label = flags.map { |flag, value| "#{flag}=#{value}" }.join(', ')

    it "applies all four installation/account gates consistently (#{label})" do
      result = result_for(flags)
      expected = flags.values.all?

      expect(result.available).to eq(expected)
      expect(result.can_choose_internal).to eq(expected)
      expect(result.reasons).to be_an(Array)
      expect(result.reasons).to be_empty if expected
      expect(result.reasons).not_to be_empty unless expected
    end
  end

  it 'evaluates autonomy availability for the requested account' do
    other_account = create(:account)
    allow(Crm::Config).to receive(:enabled?).and_return(true)
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Autonomia::Agents::Config).to receive(:enabled?).with(account).and_return(true)
    allow(Autonomia::Agents::Config).to receive(:enabled?).with(other_account).and_return(false)

    with_modified_env CRM_COPILOT_ENABLED: 'true' do
      result = service_class.new(account: account).call
      expect(result.available).to be(true)
      expect(result.can_choose_internal).to be(true)
    end

    expect(Autonomia::Agents::Config).to have_received(:enabled?).with(account)
  end
end
