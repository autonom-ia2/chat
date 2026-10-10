require 'rails_helper'

# Endereços da importação (#1099): lidos como o navegador lê — espaço e acento dentro do nome são codificados, nunca
# apagados; o esquema continua lido sem os caracteres de controle que o navegador ignora.
RSpec.describe EmailCampaigns::Import::Url, :aggregate_failures do
  let(:base) { 'https://arquivo-importado.invalid/pasta/' }

  it 'resolves a relative name with spaces and accents by encoding them' do
    expect(described_class.resolve('../img/minha foto.png', base)).to eq('https://arquivo-importado.invalid/img/minha%20foto.png')
    expect(described_class.resolve('promoção.png', base)).to eq('https://arquivo-importado.invalid/pasta/promo%C3%A7%C3%A3o.png')
    expect(described_class.resolve("  img/a%20b.png\n", base)).to eq('https://arquivo-importado.invalid/pasta/img/a%20b.png')
  end

  it 'cleans an absolute address the same way, dropping only line breaks and the blanks around it' do
    expect(described_class.clean(" https://cdn.example.com/minha foto.png\t")).to eq('https://cdn.example.com/minha%20foto.png')
    expect(described_class.clean("https://cdn.exa\nmple.com/a.png")).to eq('https://cdn.example.com/a.png')
  end

  it 'still reads the scheme the way a browser does' do
    expect(described_class.scheme("java\tscript:alert(1)")).to eq('javascript')
    expect(described_class.http?(' https://x.example.com')).to be(true)
  end
end
