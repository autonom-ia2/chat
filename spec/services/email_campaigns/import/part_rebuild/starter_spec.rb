require 'rails_helper'

# O clique em "Refazer para editar" (#1099, entrega D): só com a IA configurada, numa importação pronta, num trecho que
# ainda é imagem, uma vez por trecho, até PartRebuild::MAX_PER_IMPORT trechos por importação e dentro do teto mensal da
# conta. Conta o trecho, marca "refazendo" com um token novo e manda para o job.
RSpec.describe EmailCampaigns::Import::PartRebuild::Starter, :aggregate_failures do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:placeholders) { EmailCampaigns::Import::Placeholders }
  let(:parts) { (1..6).map { |index| "trecho-#{index}" } }
  let(:body) do
    images = parts.map do |id|
      %(<mj-image src="#{placeholders::UNRESOLVED_SRC}" css-class="#{placeholders::UNRESOLVED_CLASS}" title="#{id}" alt="Parte"></mj-image>)
    end
    "<mj-section><mj-column>#{images.join}</mj-column></mj-section>"
  end
  let(:mjml) { EmailCampaigns::LockedFooter.ensure("<mjml><mj-body>#{body}</mj-body></mjml>") }
  let(:report) { { 'unresolved' => parts.map { |id| { 'id' => id, 'text' => 'Parte', 'html' => '<p>Parte</p>' } } } }
  let(:import) do
    EmailCampaignTemplateImport.create!(account: account, source_kind: 'paste', status: 'ready', result_mjml: mjml, report: report)
  end
  let(:configured) { true }

  before do
    resolver = instance_double(Crm::Ai::CredentialResolver, configured?: configured)
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolver)
  end

  def start(target)
    described_class.call(import, target)
  end

  def refused(target)
    start(target)
    nil
  rescue EmailCampaigns::Import::Error => e
    e.code
  end

  it 'counts the part, marks it running and hands it to the job' do
    expect { start('trecho-1') }.to have_enqueued_job(EmailCampaigns::Import::RebuildJob)
      .with(import.id, 'trecho-1', satisfy { |token| token == import.reload.rebuilds.dig('trecho-1', 'token') })

    entry = import.reload.rebuilds['trecho-1']
    expect(entry).to include('status' => 'running', 'period' => Time.current.utc.to_date.beginning_of_month.iso8601)
    expect(entry['token'].length).to eq(24)
    expect(EmailTemplateImportAiQuota.find_by(account: account).used).to eq(1)
  end

  it 'sends each part once, and at most five parts of one import' do
    start('trecho-1')
    expect(refused('trecho-1')).to eq(:rebuild_running)
    import.update!(rebuilds: import.rebuilds.merge('trecho-1' => import.rebuilds['trecho-1'].merge('status' => 'failed')))
    expect(refused('trecho-1')).to eq(:rebuild_used)

    %w[trecho-2 trecho-3 trecho-4 trecho-5].each { |id| start(id) }
    expect(refused('trecho-6')).to eq(:rebuild_limit)
    expect(EmailTemplateImportAiQuota.find_by(account: account).used).to eq(5)
  end

  it 'stops at the monthly ceiling of the account, without touching the import' do
    EmailTemplateImportAiQuota.create!(account: account, period: Time.current.utc.to_date.beginning_of_month,
                                       used: EmailCampaigns::Import::PartRebuild::Quota::PER_MONTH)

    import
    expect { expect(refused('trecho-1')).to eq(:rebuild_month_limit) }.not_to have_enqueued_job(EmailCampaigns::Import::RebuildJob)
    expect(import.reload.rebuilds).to eq({})
  end

  it 'refuses a part that is no longer an image, and an import that is not ready' do
    expect(refused('trecho-99')).to eq(:fix_gone)
    import.update!(status: 'saved')
    expect(refused('trecho-1')).to eq(:not_ready)
    expect(EmailTemplateImportAiQuota.count).to eq(0)
  end

  context 'when the AI is not configured' do
    let(:configured) { false }

    it 'refuses without counting anything' do
      expect(refused('trecho-1')).to eq(:ai_not_configured)
      expect(EmailTemplateImportAiQuota.count).to eq(0)
      expect(import.reload.rebuilds).to eq({})
    end
  end
end
