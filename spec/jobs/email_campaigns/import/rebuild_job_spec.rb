require 'rails_helper'

# O job de "Refazer para editar" (#1099, entrega D): roda o PartRebuild do clique (importação, trecho e token) e não faz
# nada quando a importação sumiu.
RSpec.describe EmailCampaigns::Import::RebuildJob do
  it 'rebuilds the part of the click' do
    import = create(:account).then { |account| EmailCampaignTemplateImport.create!(account: account, source_kind: 'paste') }
    allow(EmailCampaigns::Import::PartRebuild).to receive(:call)

    described_class.perform_now(import.id, 'trecho-1', 'token')
    described_class.perform_now(0, 'trecho-1', 'token')

    expect(EmailCampaigns::Import::PartRebuild).to have_received(:call).once.with(import, 'trecho-1', 'token')
  end

  it 'never asks the AI again when the job runs a second time for the same click' do
    account = create(:account)
    import = EmailCampaignTemplateImport.create!(account: account, source_kind: 'paste', status: 'ready',
                                                 report: { 'unresolved' => [{ 'id' => 'trecho-1', 'text' => 'Oi', 'html' => '<p>Oi</p>' }] },
                                                 rebuilds: { 'trecho-1' => { 'status' => 'running', 'token' => 'token', 'period' => '2026-10-01',
                                                                             'started_at' => Time.current.iso8601 } })
    client = instance_double(Crm::Ai::ResponsesClient)
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k' }))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
    allow(client).to receive(:create).and_return({ text: { mjml: '<mj-section><mj-column><mj-text>Oi</mj-text></mj-column></mj-section>' }.to_json })
    allow(EmailCampaignTemplateImport).to receive(:find_by).and_return(import)
    allow(import).to receive(:update!).and_call_original
    allow(import).to receive(:update!).with(rebuilds: hash_including('trecho-1' => hash_including('status' => 'failed')))
                                      .and_raise(ActiveRecord::ConnectionNotEstablished)

    # The first run is paid for and then fails to store its end: Sidekiq would run the job again.
    expect { described_class.perform_now(import.id, 'trecho-1', 'token') }.to raise_error(ActiveRecord::ConnectionNotEstablished)
    described_class.perform_now(import.id, 'trecho-1', 'token')

    expect(client).to have_received(:create).once
  end
end
