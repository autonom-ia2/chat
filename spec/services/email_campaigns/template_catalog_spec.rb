require 'rails_helper'

RSpec.describe EmailCampaigns::TemplateCatalog, :aggregate_failures do
  it 'keeps the thirteen pt-BR designs addressable and uniquely keyed' do
    entries = described_class.entries

    expect(entries.size).to eq(13)
    expect(entries.map { |entry| entry.fetch('key') }.uniq.size).to eq(entries.size)
    expect(entries.map { |entry| entry.fetch('name') }.uniq.size).to eq(entries.size)
    expect(entries.map { |entry| entry.fetch('name') } & described_class.retired_names).to be_empty

    entries.each do |entry|
      source = described_class::ROOT.join(entry.fetch('path'))
      expect(source).to exist
      expect(source.extname).to eq('.mjml')
      expect(described_class.html_path(entry)).to exist
      expect(described_class.html_path(entry).read).to include('footer-locked', '{{ unsubscribe_url }}')
    end
  end

  it 'sanitizes every design idempotently while preserving the protected unsubscribe footer' do
    described_class.entries.each do |entry|
      first = described_class.body(entry)

      expect(described_class.body(entry)).to eq(first)
      expect(first).to include('footer-locked', '{{ unsubscribe_url }}')
    end
  end

  it 'exposes catalog keys only for shared templates' do
    entry = described_class.entries.first
    template = Struct.new(:account_id, :name)

    expect(described_class.key_for(template.new(nil, entry.fetch('name')))).to eq(entry.fetch('key'))
    expect(described_class.key_for(template.new(123, entry.fetch('name')))).to be_nil
  end

  it 'points the published MJML and HTML images at this installation' do
    entry = described_class.entries.find { |item| item.fetch('key') == 'boas-vindas' }

    mjml, html = described_class.published(entry, base_url: 'https://chat.exemplo.com.br')

    image = 'https://chat.exemplo.com.br/email-templates/biblioteca/01-boas-vindas.jpg'
    expect(mjml).to include(%(src="#{image}"))
    expect(html).to include(%(src="#{image}"))
    expect([mjml, html]).to all(satisfy { |markup| markup.exclude?('src="/email-templates/') })
    expect(html).to include('{{ unsubscribe_url }}')
  end

  it 'refuses to publish without an absolute installation URL' do
    entry = described_class.entries.first

    expect { described_class.published(entry, base_url: nil) }.to raise_error(ArgumentError)
    expect { described_class.published(entry, base_url: 'chat.exemplo.com.br') }.to raise_error(ArgumentError)
  end
end
