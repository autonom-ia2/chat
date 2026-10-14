require 'rails_helper'

RSpec.describe Crm::AgentAvailability do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }

  def build_with(hours)
    described_class.new(account: account, user: user, working_hours: hours)
  end

  it 'aceita seguir a página (sem horas próprias) e horas no formato da página' do
    expect(build_with({})).to be_valid
    expect(build_with('start_hour' => 9, 'end_hour' => 12, 'weekdays' => [1, 3])).to be_valid
  end

  it 'recusa horas incompletas, invertidas, fora do dia, em texto e dias inválidos' do
    [
      { 'start_hour' => 9, 'end_hour' => 12 },
      { 'start_hour' => 12, 'end_hour' => 9, 'weekdays' => [1] },
      { 'start_hour' => 9, 'end_hour' => 25, 'weekdays' => [1] },
      { 'start_hour' => '9', 'end_hour' => 12, 'weekdays' => [1] },
      { 'start_hour' => 9, 'end_hour' => 12, 'weekdays' => [] },
      { 'start_hour' => 9, 'end_hour' => 12, 'weekdays' => [7] },
      { 'start_hour' => 9, 'end_hour' => 12, 'weekdays' => [1, 1] }
    ].each do |hours|
      expect(build_with(hours)).not_to be_valid, hours.inspect
    end
  end

  it 'é uma por pessoa por conta e só de quem é da conta' do
    described_class.create!(account: account, user: user)

    expect(described_class.new(account: account, user: user)).not_to be_valid
    expect(described_class.new(account: account, user: create(:user))).not_to be_valid
  end
end
