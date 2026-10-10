require 'rails_helper'

RSpec.describe EmailCampaigns::TemplateLibrarySeeder, :aggregate_failures do
  let(:catalog) { EmailCampaigns::TemplateCatalog }
  let(:base_url) { 'https://chat.exemplo.com.br' }
  let(:account) { create(:account) }
  let(:retired_name) { catalog.retired_names.first }
  let!(:old_global) do
    EmailCampaignTemplate.create!(account: nil, name: retired_name, category: 'abandoned-cart',
                                  body_mjml: '<mjml><mj-body></mj-body></mjml>', body_html: '<html>old</html>')
  end
  let!(:unknown_global) do
    EmailCampaignTemplate.create!(account: nil, name: 'Global criado fora do catálogo', category: 'outro',
                                  body_mjml: '<mjml><mj-body></mj-body></mjml>', body_html: '<html>x</html>')
  end
  # An account copy that shares a retired name and a new name: both must survive untouched.
  let!(:own_templates) do
    [retired_name, catalog.entries.first.fetch('name')].map do |name|
      EmailCampaignTemplate.create!(account: account, name: name, category: 'meus-modelos',
                                    body_mjml: "<mjml><mj-body><mj-text>#{name}</mj-text></mj-body></mjml>",
                                    body_html: "<html>#{name}</html>", thumbnail_url: 'https://exemplo.com/t.png')
    end
  end

  def fingerprint(records)
    records.map { |record| record.reload.attributes }
  end

  it 'plans without writing anything' do
    before = fingerprint(EmailCampaignTemplate.order(:id).to_a)

    report = described_class.new(base_url: base_url).plan

    expect(report.created.size).to eq(13)
    expect(report.retired.map(&:name)).to eq([retired_name])
    expect(report.unknown.map(&:name)).to eq([unknown_global.name])
    expect(fingerprint(EmailCampaignTemplate.order(:id).to_a)).to eq(before)
  end

  it 'publishes the thirteen designs, retires only the old globals and never touches account templates' do
    own_before = fingerprint(own_templates)

    described_class.new(base_url: base_url).apply!

    globals = EmailCampaignTemplate.global
    expect(globals.where(name: catalog.entries.map { |entry| entry.fetch('name') }).count).to eq(13)
    expect(EmailCampaignTemplate.exists?(old_global.id)).to be(false)
    expect(EmailCampaignTemplate.exists?(unknown_global.id)).to be(true)
    expect(fingerprint(own_templates)).to eq(own_before)

    welcome = globals.find_by!(name: 'Boas-vindas')
    expect(welcome.category).to eq('relacionamento')
    expect(welcome.body_mjml).to include("#{base_url}/email-templates/biblioteca/01-boas-vindas.jpg")
    expect(welcome.body_html).to include("#{base_url}/email-templates/biblioteca/01-boas-vindas.jpg", '{{ unsubscribe_url }}')
  end

  it 'is idempotent: a second run reports everything unchanged and keeps the records' do
    described_class.new(base_url: base_url).apply!
    ids = EmailCampaignTemplate.global.order(:id).pluck(:id, :updated_at)

    report = described_class.new(base_url: base_url).apply!

    expect(report.unchanged.size).to eq(13)
    expect(report.created + report.updated + report.retired).to be_empty
    expect(EmailCampaignTemplate.global.order(:id).pluck(:id, :updated_at)).to eq(ids)
  end

  it 'updates a published design whose content changed' do
    described_class.new(base_url: base_url).apply!
    EmailCampaignTemplate.global.find_by!(name: 'Boas-vindas').update!(body_html: '<html>editado</html>')

    report = described_class.new(base_url: base_url).apply!

    expect(report.updated.map { |entry| entry.fetch('key') }).to eq(['boas-vindas'])
  end

  it 'requires the installation URL before planning' do
    expect { described_class.new(base_url: '').plan }.to raise_error(ArgumentError)
  end

  describe 'rake email_campaign_templates:seed' do
    let(:task) { Rake::Task['email_campaign_templates:seed'] }

    before { Rails.application.load_tasks unless Rake::Task.task_defined?('email_campaign_templates:seed') }

    def run_task(env)
      task.reenable
      with_modified_env(env) { expect { task.invoke }.to output.to_stdout }
    end

    it 'only reports by default and writes with APPLY=1' do
      run_task(FRONTEND_URL: base_url, APPLY: nil)
      expect(EmailCampaignTemplate.global.count).to eq(2)

      run_task(FRONTEND_URL: base_url, APPLY: '1')
      expect(EmailCampaignTemplate.global.pluck(:name)).to contain_exactly(unknown_global.name, *catalog.entries.map { |entry| entry.fetch('name') })
    end
  end
end
