require 'rails_helper'

# Retenção do consultor (#1110, F5): runs com mais de 90 dias, ações com mais de 400 e janelas de frequência com
# mais de 35 saem; o resto fica. Apagar o run não apaga a ação, só solta a ligação.
RSpec.describe Crm::MetaAds::Advisor::PruneJob do
  let(:account) { create(:account) }
  let(:today) { Date.new(2026, 10, 7) }

  def run_on(date, signature)
    Crm::MetaAdvisorRun.create!(account: account, ad_account_id: '9001', local_date: date, locale: 'pt_BR', signature: signature,
                                rules_version: 'f5.1', trigger: 'panel')
  end

  def action_on(date, run: nil)
    Crm::MetaAdvisorAction.create!(account: account, local_date: date, kind: 'stalled_quotes', subject_key: 'account', position: 1, run: run)
  end

  def window_until(date)
    Crm::MetaAdFrequencyWindow.create!(account: account, ad_account_id: '9001', ad_id: 'A', window_days: 7, date_end: date, frequency: 2,
                                       fetched_at: Time.current)
  end

  it 'apaga só o que passou do prazo de cada tabela' do
    travel_to(Time.zone.parse('2026-10-07T05:30:00-03:00')) do
      old_run = run_on(today - 91, 'a' * 64)
      kept_run = run_on(today - 90, 'b' * 64)
      orphaned = action_on(today - 91, run: old_run)
      old_action = action_on(today - 401)
      kept_action = action_on(today - 400)
      old_window = window_until(today - 36)
      kept_window = window_until(today - 35)

      described_class.perform_now

      expect(Crm::MetaAdvisorRun.pluck(:id)).to eq([kept_run.id])
      expect(Crm::MetaAdvisorAction.pluck(:id)).to contain_exactly(orphaned.id, kept_action.id)
      expect(orphaned.reload.run_id).to be_nil
      expect(Crm::MetaAdvisorAction.exists?(old_action.id)).to be(false)
      expect(Crm::MetaAdFrequencyWindow.pluck(:id)).to eq([kept_window.id])
      expect(Crm::MetaAdFrequencyWindow.exists?(old_window.id)).to be(false)
    end
  end

  it 'apaga em lotes, sem limite de quantidade' do
    stub_const("#{described_class}::BATCH", 2)
    travel_to(Time.zone.parse('2026-10-07T05:30:00-03:00')) do
      5.times { |index| window_until(today - 40 - index) }

      described_class.perform_now

      expect(Crm::MetaAdFrequencyWindow.count).to eq(0)
    end
  end

  it 'roda na fila low, todo dia às 08:30 UTC (5h30 de Brasília)' do
    entry = YAML.load_file(Rails.root.join('config/schedule.yml')).fetch('crm_meta_ads_advisor_prune_job')

    expect(entry).to include('cron' => '30 8 * * *', 'class' => described_class.name, 'queue' => 'low')
    expect(described_class.new.queue_name).to eq('low')
  end
end
