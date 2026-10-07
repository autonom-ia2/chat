require 'rails_helper'

RSpec.describe EmailCampaigns::Import::StyleInliner, :aggregate_failures do
  let(:report) { EmailCampaigns::Import::Report.new(source_kind: 'paste') }

  def inline(css, body, **)
    doc = Nokogiri::HTML5("<html><head><style>#{css}</style></head><body>#{body}</body></html>")
    described_class.call(doc, report, **)
    doc
  end

  def warning(code)
    report.to_h[:warnings].find { |entry| entry[:code] == code }
  end

  it 'writes the stylesheet rules into the tags, by specificity and order, without beating inline or !important' do
    doc = inline('p { color:#111111; font-size:14px } .destaque { color:#222222 } #um { color:#333333 } ' \
                 'td p { line-height:20px } .forte { font-weight:bold !important }',
                 '<table><tr><td><p id="um" class="destaque">A</p><p class="destaque" style="color:#444444">B</p>' \
                 '<p class="forte" style="font-weight:normal">C</p></td></tr></table>')
    a, b, c = doc.css('p').map { |node| node['style'] }

    expect(a).to eq('color:#333333;font-size:14px;line-height:20px')
    expect(b).to eq('color:#444444;font-size:14px;line-height:20px')
    expect(c).to eq('color:#111111;font-size:14px;line-height:20px;font-weight:bold')
    expect(doc.css('style')).to be_empty
  end

  it 'ignores media queries, pseudo selectors, at-rules and never follows @import' do
    doc = inline("@import url('https://cdn.example.net/x.css'); @font-face { font-family:M; src:url(m.woff) } " \
                 '@media (max-width:600px) { .col { display:none !important } } a:hover { color:red } ' \
                 '@media (prefers-color-scheme: dark) { .x { color:#fff } } .col { width:50% }',
                 '<div class="col"><a href="https://a.example.com">x</a></div>')

    expect(doc.at('div')['style']).to eq('width:50%')
    expect(doc.at('a')['style']).to be_nil
    expect(warning(:web_font_ignored)).to be_present
    expect(warning(:dark_mode_ignored)).to be_present
  end

  it 'stops at the rule ceiling and reports it' do
    css = Array.new(EmailCampaigns::Import::Limits::MAX_CSS_RULES + 5) { |index| ".c#{index} { color:#000000 }" }.join(' ')
    doc = inline(css, %(<p class="c0">a</p><p class="c#{EmailCampaigns::Import::Limits::MAX_CSS_RULES + 1}">b</p>))

    expect(doc.css('p').map { |node| node['style'] }).to eq(['color:#000000', nil])
    expect(warning(:css_limit)[:count]).to eq(1)
  end

  it 'stops when its own time budget runs out' do
    ticks = [0.0, 0.0, 10.0].each
    doc = inline('.a { color:#000000 } .b { color:#111111 }', '<p class="a">a</p><p class="b">b</p>',
                 deadline: 1.0, clock: -> { ticks.next })

    expect(doc.css('p').map { |node| node['style'] }).to eq(['color:#000000', nil])
    expect(warning(:css_limit)[:count]).to eq(1)
  end
end
