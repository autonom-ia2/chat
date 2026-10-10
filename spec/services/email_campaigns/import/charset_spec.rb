require 'rails_helper'

# Codificação da entrada (#1099, entrega B): um .html ou página em ISO-8859-1/Windows-1252 chega com os acentos — pelo
# charset do cabeçalho, pelo <meta charset> ou, sem nenhum dos dois, pela codificação ocidental que o navegador usa — e
# o que ainda assim não puder ser lido sai com aviso, nunca calado.
RSpec.describe EmailCampaigns::Import::Charset, :aggregate_failures do
  def page(head, body)
    "<html><head>#{head}</head><body><table width=\"600\"><tr><td><p>#{body}</p></td></tr></table></body></html>"
  end

  def latin(text)
    text.encode(Encoding::Windows_1252).b
  end

  def import(bytes, charset: nil)
    EmailCampaigns::Import::Engine.call(bytes, source_kind: 'file', charset: charset)
  end

  it 'reads the <meta charset> of a page that is not UTF-8' do
    result = import(latin(page('<meta charset="iso-8859-1">', 'Promoção de verão — só hoje')))

    expect(result.mjml).to include('Promoção de verão — só hoje')
    expect(result.report.count(:characters_replaced)).to eq(0)
  end

  it 'reads the older http-equiv declaration' do
    head = '<meta http-equiv="Content-Type" content="text/html; charset=windows-1252">'

    expect(import(latin(page(head, 'Atenção'))).mjml).to include('Atenção')
  end

  it 'prefers the charset the address answered with' do
    # 0xA4 is the euro sign in ISO-8859-15 and "¤" in Windows-1252: only the declared charset reads it right.
    bytes = page('', 'Liquidação por 10 €').encode(Encoding::ISO_8859_15).b

    expect(import(bytes, charset: 'iso-8859-15').mjml).to include('Liquidação por 10 €')
  end

  it 'falls back to the western encoding of browsers when nothing is declared' do
    expect(import(latin(page('', 'Inscrição aberta'))).mjml).to include('Inscrição aberta')
  end

  it 'keeps UTF-8 as it is, with or without the BOM' do
    result = import("﻿#{page('<meta charset="iso-8859-1">', 'Ação')}")

    expect(result.mjml).to include('Ação')
    expect(result.report.count(:characters_replaced)).to eq(0)
  end

  it 'warns, instead of dropping in silence, when bytes cannot be read in the declared encoding' do
    broken = page('<meta charset="utf-8">', 'Oferta X').b.sub('X'.b, "\xC3\x28".b)

    result = import(broken)

    expect(result.mjml).to include('Oferta')
    expect(result.report.count(:characters_replaced)).to eq(1)
    expect(result.report.to_h[:warnings]).to include(hash_including(code: :characters_replaced, severity: :warning))
  end
end
