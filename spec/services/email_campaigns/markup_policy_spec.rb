require 'rails_helper'

RSpec.describe EmailCampaigns::MarkupPolicy, :aggregate_failures do
  it 'keeps http, https, mailto, tel and addresses without a scheme' do
    ['https://x.test/a', 'HTTP://x.test', 'mailto:oi@x.test', 'tel:+55119', '/p?x=1', '#topo', '?a=1', '{{ unsubscribe_url }}', ''].each do |url|
      expect(described_class.safe_url?(url)).to be(true), url
    end
  end

  it 'refuses any other scheme, however it is encoded' do
    ['javascript:x', ' JaVaScRiPt:x', "java\tscript:x", "\u0001javascript:x", 'java&#x09;script:x', 'javascript&colon;x',
     '&#106;avascript:x', '&amp;#106;avascript:x', '&amp;amp;#x6A;avascript:x', 'vbscript:x', 'data:text/html,x', 'file:///etc'].each do |url|
      expect(described_class.safe_url?(url)).to be(false), url
    end
  end

  it 'lets Liquid into an address only as the unsubscribe placeholder or after a fixed safe scheme' do
    ['{{ unsubscribe_url }}', '{{unsubscribe_url}}', 'https://x.test/?c={{ nome }}', 'HTTPS://{{ dominio }}', 'mailto:{{ email }}',
     'tel:{{ fone }}', 'https://x.test/a'].each do |url|
      expect(described_class.safe_template_url?(url)).to be(true), url
    end
    ['{% if x %}javascript:alert(1){% endif %}', 'https://x.test/{% if x %}y{% endif %}', '{{ link }}', '/p?x={{ id }}', 'https:{{ x }}',
     '&#123;&#123; link }}', '&#123;% if x %}'].each do |url|
      expect(described_class.safe_template_url?(url)).to be(false), url
      expect(described_class.safe_url?(url)).to be(false), url
    end
  end

  it 'applies the same Liquid rule to imported links and images' do
    report = EmailCampaigns::Import::Report.new(source_kind: 'paste')
    links = EmailCampaigns::Import::LinkPolicy.new(report)

    expect(links.href('{{ unsubscribe_url }}')).to eq('{{ unsubscribe_url }}')
    expect(links.href('https://x.test/?c={{ nome }}')).to eq('https://x.test/?c=%7B%7B%20nome%20%7D%7D') # encoded, inert as before
    expect(links.href('https://x.test/{% if x %}a{% endif %}')).to be_nil
    expect(links.href('{{ link }}')).to be_nil
    expect(links.image('https://x.test/{% if x %}a.png{% endif %}')).to eq([nil, :missing])
  end

  it 'checks every candidate of a srcset' do
    expect(described_class.safe_url_attribute?('srcset', 'https://x.test/a.png 1x, https://x.test/b.png 2x')).to be(true)
    expect(described_class.safe_url_attribute?('srcset', 'https://x.test/a.png 1x, javascript:x 2x')).to be(false)
  end

  it 'refuses every url() for the import and only non-http ones for the AI path' do
    expect(described_class.unsafe_css?('url(https://x.test/a.png)')).to be(true)
    expect(described_class.unsafe_style?('background:url("https://x.test/a.png")')).to be(false)
    expect(described_class.unsafe_style?('background:url(data:image/svg+xml,x)')).to be(true)
    ['width:expression(alert(1))', 'behavior:url(x.htc)', '-moz-binding:url(https://x.test/x.xml)', 'background:u\\72l(x)',
     'color:red;</style>', 'x:java&#115;cript:y'].each do |css|
      expect(described_class.unsafe_style?(css)).to be(true), css
    end
  end

  it 'tells active elements and event handlers apart from the rest' do
    expect(%w[script SVG svg:script math iframe form].map { |name| described_class.unsafe_element?(name) }).to all(be(true))
    expect(%w[p table img a].map { |name| described_class.unsafe_element?(name) }).to all(be(false))
    expect(described_class.event_handler?('OnError')).to be(true)
    expect(described_class.event_handler?('href')).to be(false)
  end
end
