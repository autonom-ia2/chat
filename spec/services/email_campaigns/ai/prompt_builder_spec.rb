require 'rails_helper'

RSpec.describe EmailCampaigns::Ai::PromptBuilder, :aggregate_failures do
  let(:instructions) { described_class.generate(brand: 'Padaria Pão Quente') }

  it 'uses the account brand instead of a hardcoded one' do
    expect(instructions).to include('Padaria Pão Quente')
    expect(instructions).not_to include('Hub2you', 'hub2you', 'Autonomia', 'Av. Exemplo')
  end

  it 'teaches MJML with explicit close tags only' do
    expect(instructions).to include('<mj-all font-family="Arial, Helvetica, sans-serif"></mj-all>')
    expect(instructions.split('<br/>').join).not_to include('/>')
  end

  it 'forbids markdown and source citations in the copy' do
    expect(instructions).to include('markdown')
    expect(instructions).to include('<a href')
  end

  it 'keeps the locked footer with the unsubscribe link and social links only when provided' do
    expect(instructions).to include('footer-locked', '{{ unsubscribe_url }}')
    expect(instructions).to include('mj-social SOMENTE')
  end
end
