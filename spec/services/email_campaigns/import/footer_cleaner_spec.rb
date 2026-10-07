require 'rails_helper'

# The source platform's footer leaves an imported model (#1099) — and only the footer: the body text that shares a block
# with the unsubscribe link stays.
RSpec.describe EmailCampaigns::Import::FooterCleaner, :aggregate_failures do
  def import(input)
    EmailCampaigns::Import::Engine.call(input, source_kind: 'paste')
  end

  def content(result)
    out = Nokogiri::HTML5.fragment(result.mjml)
    out.css('mj-section').reject { |section| section['css-class'].to_s.include?('footer-locked') }.map(&:to_html).join
  end

  def codes(result)
    result.report.to_h[:warnings].pluck(:code)
  end

  def email(cell)
    %(<table width="600"><tr><td>#{cell}</td></tr></table>)
  end

  let(:body) do
    '<p>Nossa coleção de outono chegou com peças leves para os dias amenos.</p>' \
      '<p>Frete grátis em todo o site até domingo, sem valor mínimo.</p><p>Use o cupom OUTONO10 no carrinho.</p>'
  end

  it 'takes only the footer lines out of a block that also holds the body' do
    result = import(email("#{body}<p>Não quer mais receber? <a href=\"*|UNSUB|*\">Descadastre-se</a></p><p>Loja Exemplo, Rua A, 10</p>"))

    expect(content(result)).to include('coleção de outono', 'Frete grátis', 'OUTONO10')
    expect(content(result)).not_to include('Descadastre-se', 'Rua A')
    expect(result.report.dropped_texts).to include({ text: 'Não quer mais receber? Descadastre-se Loja Exemplo, Rua A, 10', reason: :footer })
    expect(result.mjml.scan('{{ unsubscribe_url }}').size).to eq(1)
  end

  it 'keeps the body even when nothing else is in the model' do
    expect { import(email("#{body}<p><a href=\"{{ unsubscribe }}\">Sair da lista</a></p>")) }.not_to raise_error
  end

  it 'keeps the promotion of an MJML text block that ends with the unsubscribe link' do
    result = import('<mjml><mj-body><mj-section><mj-column><mj-text><p>Promoção de aniversário: 30% em toda a loja, só hoje.</p>' \
                    '<p><a href="{{ unsubscribe }}">Cancelar</a></p></mj-text></mj-column></mj-section></mj-body></mjml>')

    expect(content(result)).to include('Promoção de aniversário')
    expect(content(result)).not_to include('Cancelar')
  end

  it 'takes only the link out when long text follows it, and says so' do
    after = '<p>Texto do corpo que segue depois do link e que não é rodapé nenhum, com bastante conteúdo para ler.</p>' * 5
    result = import(email("<p>Oi! <a href=\"*|UNSUB|*\">Sair</a></p>#{after}"))

    expect(content(result)).to include('Oi!', 'Texto do corpo que segue')
    expect(content(result)).not_to include('>Sair<')
    expect(codes(result)).to include(:unsubscribe_link_removed)
  end

  it 'removes an unsubscribe link hidden in a social icon, and still adds our footer' do
    result = import('<mjml><mj-body><mj-section><mj-column><mj-text>Conteúdo</mj-text><mj-social>' \
                    '<mj-social-element name="facebook" href="https://facebook.example.com/loja" src="https://ok.example.com/f.png">' \
                    'FB</mj-social-element>' \
                    '<mj-social-element name="x" href="*|UNSUB|*" src="https://ok.example.com/x.png">Sair</mj-social-element>' \
                    '</mj-social></mj-column></mj-section></mj-body></mjml>')

    expect(content(result)).to include('facebook.example.com/loja', 'Conteúdo')
    expect(content(result)).not_to include('unsubscribe_url')
    expect(EmailCampaigns::QualityGate.locked_footers(result.mjml).size).to eq(1)
    expect(EmailCampaigns::QualityGate.locked_footers(result.mjml).first).not_to include('Conteúdo', 'facebook')
  end

  it 'reports the footer as replaced only when one was taken out' do
    expect(codes(import(email('<p>Só conteúdo</p>')))).not_to include(:footer_replaced)
    expect(codes(import(email("#{body}<p><a href=\"*|UNSUB|*\">Sair</a></p>")))).to include(:footer_replaced)
  end

  it 'records the text left behind by an unsubscribe tag written as plain text' do
    result = import(email('<p>Conteúdo</p><p>Para sair: *|UNSUB|*</p>'))

    expect(result.report.items(:unsubscribe_text_kept)).to include('Para sair:')
  end
end
