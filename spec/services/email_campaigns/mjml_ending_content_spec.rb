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

  # Reading a character by its index in accented text costs a scan from the start each time, which made long designs
  # quadratic (#1099). The cut reads the source by byte offsets only; this checks it, without timing it (#2241).
  it 'reads a long design with accented text by byte offsets, never by character index' do
    long = "<mjml><mj-body><mj-section><mj-column>#{'<mj-text>Promoção de ação · já</mj-text>' * 6_000}</mj-column></mj-section></mj-body></mjml>"
    %i[[] slice each_char chars].each { |reader| allow(long).to receive(reader).and_call_original }
    cut = described_class.new(long)
    cut.skeleton

    %i[[] slice each_char chars].each { |reader| expect(long).not_to have_received(reader) }
    expect(cut.slots.size).to eq(6_000)
  end
end
