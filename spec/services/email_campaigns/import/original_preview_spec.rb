require 'rails_helper'

# A prévia "Como era" da tela de importação (#1099, entrega C): o original passa pela mesma limpeza do motor, as imagens
# apontam só para as cópias da importação (as que não vieram ficam cinza) e nenhum link leva para fora. A tela mostra
# isso num iframe sandbox="" — nada da página de origem rastreia quem abre a prévia.
RSpec.describe EmailCampaigns::Import::OriginalPreview, :aggregate_failures do
  let(:copy) { 'https://app.exemplo.com.br/rails/active_storage/blobs/redirect/abc/logo.png' }
  let(:html) do
    <<~HTML
      <html><head><title>Outubro</title><style>.titulo{color:#3b2516}</style><script>alert(1)</script></head>
      <body style="background:#f6f1eb">
        <table width="600" align="center"><tr><td>
          <img src="https://cdn.example.com/logo.png" alt="Logo" width="200" height="60">
          <img src="https://cdn.example.com/sumiu.png" alt="Grão Vale" width="180" height="120">
          <img src="https://rastreio.example.com/open.gif" width="1" height="1">
          <p class="titulo" onclick="roubar()">Olá, {{lead.nome}}! Chegou a safra.</p>
          <a href="https://loja.example.com/safra">Quero provar</a>
          <td background="https://cdn.example.com/fundo.jpg">Banner</td>
        </td></tr></table>
      </body></html>
    HTML
  end

  def preview(markup = html, copies: { 'https://cdn.example.com/logo.png' => copy })
    described_class.call(markup, copies: copies)
  end

  it 'keeps the look of the original with its text, cleaned like the import' do
    out = preview
    doc = Nokogiri::HTML5(out)

    expect(doc.at_css('meta[charset]')).to be_present
    expect(doc.text).to include('Chegou a safra', 'Quero provar')
    expect(doc.at_css('p')['style']).to include('color')
    expect(out).not_to include('<script', 'alert(1)', 'onclick', 'roubar')
  end

  it 'shows the fields as the person wrote them, not converted to ours' do
    text = Nokogiri::HTML5(preview).text

    expect(text).to include('Olá, {{lead.nome}}!')
    expect(text).not_to include('{{ nome }}')
  end

  it 'shows only the copies of the import and turns the other images grey' do
    doc = Nokogiri::HTML5(preview)

    expect(doc.css('img').pluck('src')).to eq([copy])
    grey = doc.css('[data-import-gray]')
    expect(grey.size).to eq(1)
    expect(grey.first['style']).to include('180px', '120px')
    expect(doc.to_html).not_to include('cdn.example.com', 'rastreio.example.com')
  end

  it 'never takes the person out of the preview through a link' do
    doc = Nokogiri::HTML5(preview)

    expect(doc.css('[href]')).to be_empty
    expect(doc.at_css('a').text).to eq('Quero provar')
  end

  it 'uses a copied section background and drops one that did not come' do
    copied = preview(copies: { 'https://cdn.example.com/fundo.jpg' => copy })
    expect(copied).to include("background-image:url(#{copy})")
    expect(preview(copies: {})).not_to include('fundo.jpg', 'background-image')
    expect(preview(copies: {})).not_to include('data-import-bg')
  end

  it 'has nothing to show for a model that was already MJML, or one it cannot read' do
    expect(preview('<mjml><mj-body><mj-section><mj-column><mj-text>Oi</mj-text></mj-column></mj-section></mj-body></mjml>')).to be_nil
    expect(preview("<html><body>#{'<div>' * 60}fundo#{'</div>' * 60}</body></html>")).to be_nil
    expect(preview('')).to be_nil
  end

  it 'is not kept when it would be too big' do
    stub_const("#{described_class}::MAX_BYTES", 200)
    expect(preview).to be_nil
  end
end
