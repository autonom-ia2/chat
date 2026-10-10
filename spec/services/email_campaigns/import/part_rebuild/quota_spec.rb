require 'rails_helper'

# O teto mensal de "Refazer para editar" por conta (#1099, entrega D): conta um por trecho, num único comando atômico,
# nunca passa de PER_MONTH, recomeça a cada mês e devolve um quando a IA nem chegou a ser chamada.
RSpec.describe EmailCampaigns::Import::PartRebuild::Quota, :aggregate_failures do
  let(:account) { create(:account) }
  let(:other) { create(:account) }
  let(:october) { Time.zone.parse('2026-10-15 12:00') }

  it 'counts one part at a time, per account and per month, and stops at the ceiling' do
    stub_const("#{described_class}::PER_MONTH", 2)

    expect(described_class.take(account, october)).to eq(Date.new(2026, 10, 1))
    expect(described_class.take(account, october)).to eq(Date.new(2026, 10, 1))
    expect(described_class.take(account, october)).to be_nil
    expect(described_class.left(account, october)).to eq(0)

    expect(described_class.take(other, october)).to eq(Date.new(2026, 10, 1))
    expect(described_class.take(account, october + 1.month)).to eq(Date.new(2026, 11, 1))
    expect(EmailTemplateImportAiQuota.find_by(account: account, period: Date.new(2026, 10, 1)).used).to eq(2)
  end

  it 'gives one back to the month it was taken in, never below zero' do
    period = described_class.take(account, october)
    described_class.give_back(account, period)
    described_class.give_back(account, period)

    expect(EmailTemplateImportAiQuota.find_by(account: account).used).to eq(0)
    expect(described_class.left(account, october)).to eq(described_class::PER_MONTH)
  end
end
