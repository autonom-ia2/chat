require 'rails_helper'

# Same cases as the editor's mjmlHeadDefaults.spec.js: front and back must agree byte for byte.
RSpec.describe EmailCampaigns::MjmlHeadDefaults, :aggregate_failures do
  def doc(attributes, body)
    "<mjml><mj-head><mj-attributes>#{attributes}</mj-attributes></mj-head><mj-body>#{body}</mj-body></mjml>"
  end

  def body_of(mjml)
    mjml[(mjml.index('<mj-body>') + 9)...mjml.index('</mj-body>')]
  end

  def canonical(mjml)
    EmailCampaigns::MjmlCanonicalizer.call(mjml)
  end

  it 'follows mjml precedence: explicit > mj-class > tag default > mj-all' do
    out = canonical(doc('<mj-all color="#a00" font-size="10px" padding="1px"/><mj-text font-size="12px" padding="2px"/>' \
                        '<mj-class name="big" padding="3px" align="center"/>',
                        '<mj-text mj-class="big" align="left">x</mj-text>'))

    expect(body_of(out)).to eq('<mj-text align="left" color="#a00" font-size="12px" padding="3px">x</mj-text>')
  end

  it 'writes only attributes the target tag accepts' do
    out = canonical(doc('<mj-all font-family="Arial" line-height="2"/>',
                        '<mj-section><mj-column><mj-spacer></mj-spacer><mj-image src="a.png"/></mj-column></mj-section>'))

    expect(body_of(out)).to eq('<mj-section><mj-column><mj-spacer></mj-spacer><mj-image src="a.png"></mj-image></mj-column></mj-section>')
  end

  it 'concatenates css-class of several classes and lets later classes win' do
    out = canonical(doc('<mj-class name="a" css-class="one" color="#111"/><mj-class name="b" css-class="two" color="#222"/>',
                        '<mj-text mj-class="a b">x</mj-text>'))

    expect(body_of(out)).to eq('<mj-text css-class="one two" color="#222">x</mj-text>')
  end

  it 'applies mj-class children to descendants of an element with that class' do
    out = canonical(doc('<mj-class name="dark" background-color="#000"><mj-text color="#fff"/></mj-class>',
                        '<mj-section mj-class="dark"><mj-column><mj-text>x</mj-text></mj-column></mj-section>'))

    expect(body_of(out)).to eq('<mj-section background-color="#000"><mj-column><mj-text color="#fff">x</mj-text></mj-column></mj-section>')
  end

  it 'keeps the other head children' do
    out = canonical('<mjml><mj-head><mj-title>T</mj-title><mj-attributes><mj-all padding="0"/></mj-attributes>' \
                    '<mj-style>.a > b { color: red }</mj-style></mj-head><mj-body></mj-body></mjml>')

    expect(out).to eq('<mjml><mj-head><mj-title>T</mj-title><mj-style>.a > b { color: red }</mj-style></mj-head><mj-body></mj-body></mjml>')
  end

  it 'leaves mj-class alone when the MJML has no mj-attributes (a block fragment)' do
    fragment = '<mj-section mj-class="x"><mj-column></mj-column></mj-section>'

    expect(canonical(fragment)).to eq(fragment)
  end
end
