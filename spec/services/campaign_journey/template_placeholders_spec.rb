require 'rails_helper'

# #1005 M1/B4: template variables read and filled without regex, in a single literal pass.
RSpec.describe CampaignJourney::TemplatePlaceholders do
  it 'lists the variables of a body, positional or named, once each, in order' do
    expect(described_class.keys('Olá {{1}}, vence {{ 2 }}. {{1}} {{nome_cliente}} {{ }} {{aberto')).to eq(%w[1 2 nome_cliente])
  end

  it 'fills the variables literally, without chaining or back-references' do
    text = described_class.render('A {{1}} B {{2}} C {{9}}', '1' => '{{2}} \0 \&', '2' => 'dois')

    expect(text).to eq('A {{2}} \0 \& B dois C {{9}}')
  end
end
