require 'rails_helper'

RSpec.describe EmailCampaigns::TemplateCatalog, :aggregate_failures do
  it 'keeps the approved fourteen source designs addressable and uniquely keyed' do
    entries = described_class.entries

    expect(entries.size).to eq(14)
    expect(entries.map { |entry| entry.fetch('key') }.uniq.size).to eq(entries.size)
    expect(entries.map { |entry| entry.fetch('name') }.uniq.size).to eq(entries.size)

    entries.each do |entry|
      source = described_class::ROOT.join(entry.fetch('path'))
      expect(source).to exist
      expect(source.extname).to eq('.mjml')
      compiled = source.sub_ext('.html')
      expect(compiled).to exist
      expect(compiled.read).to include('footer-locked', '{{ unsubscribe_url }}')
    end
  end

  it 'sanitizes every design while preserving the protected unsubscribe footer' do
    described_class.entries.each do |entry|
      first = described_class.body(entry)
      second = described_class.body(entry)

      expect(first).to eq(second)
      expect(first).to include('footer-locked', '{{ unsubscribe_url }}')
      expect(first).not_to include('<!--')
    end
  end

  it 'exposes catalog keys only for shared templates' do
    entry = described_class.entries.first
    template = Struct.new(:account_id, :name)

    expect(described_class.key_for(template.new(nil, entry.fetch('name')))).to eq(entry.fetch('key'))
    expect(described_class.key_for(template.new(123, entry.fetch('name')))).to be_nil
  end

  it 'restores the shared catalog idempotently without changing account-owned templates' do
    account = create(:account)
    first_entry = described_class.entries.first
    own = EmailCampaignTemplate.create!(account: account, name: first_entry.fetch('name'), category: first_entry.fetch('category'),
                                        body_mjml: '<mjml><mj-body><mj-text>Own</mj-text></mj-body></mjml>',
                                        body_html: '<html>Own</html>')
    task = Rake::Task['email_campaign_templates:seed']

    task.reenable
    task.invoke
    task.reenable
    task.invoke

    expect(EmailCampaignTemplate.global.count).to eq(14)
    expect(EmailCampaignTemplate.where(account: account).find_by(name: own.name)).to have_attributes(
      body_mjml: own.body_mjml,
      body_html: own.body_html
    )
  end
end
