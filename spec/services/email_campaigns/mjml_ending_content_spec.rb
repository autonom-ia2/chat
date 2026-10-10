require 'rails_helper'

RSpec.describe EmailCampaigns::MjmlEndingContent, :aggregate_failures do
  let(:mjml) do
    '<mjml><mj-head><mj-title>Promoção · ação</mj-title></mj-head><mj-body><!-- comentário -- ç -->' \
      '<mj-section><mj-column><mj-image alt="seta > ação" src="https://a.example.com/ç.png"/>' \
      '<mj-text color="#000">Olá, <b>ação</b> 😀 {{ nome }}</mj-text><mj-button href="https://a.example.com">Ver já</mj-button>' \
      '</mj-column></mj-section></mj-body></mjml>'
  end

  it 'cuts ending-tag contents and comments out of text with accents and emoji, and puts them back byte for byte' do
    cut = described_class.new(mjml)
    cut.skeleton

    expect(cut.slots.map(&:tag)).to eq(['mj-title', nil, 'mj-text', 'mj-button'])
    expect(cut.slots.map(&:content)).to eq(['Promoção · ação', '<!-- comentário -- ç -->', 'Olá, <b>ação</b> 😀 {{ nome }}', 'Ver já'])
    expect(cut.skeleton).to include('alt="seta > ação"')
    expect(cut.skeleton).not_to include('Olá', 'comentário')
    expect(cut.restore(cut.skeleton)).to eq(mjml)
    expect(cut.restore(cut.skeleton).encoding).to eq(Encoding::UTF_8)
  end

  it 'reads a long design with accented text in time proportional to its size' do
    long = "<mjml><mj-body><mj-section><mj-column>#{'<mj-text>Promoção de ação · já</mj-text>' * 6_000}</mj-column></mj-section></mj-body></mjml>"
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    cut = described_class.new(long)
    cut.skeleton

    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 1
    expect(cut.slots.size).to eq(6_000)
  end
end
