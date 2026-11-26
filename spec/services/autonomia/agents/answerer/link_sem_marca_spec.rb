require 'rails_helper'

# #3237: a busca na web da OpenAI marca os links com `utm_source=openai`; o cliente não deve ver essa marca.
RSpec.describe Autonomia::Agents::Answerer::LinkSemMarca do
  def limpar(texto)
    described_class.limpar(texto)
  end

  it 'tira a marca quando é o único parâmetro, sem deixar o ?' do
    expect(limpar('Veja https://exemplo.com/clima?utm_source=openai agora')).to eq('Veja https://exemplo.com/clima agora')
  end

  it 'mantém os outros parâmetros, na mesma ordem', :aggregate_failures do
    expect(limpar('https://exemplo.com/a?x=1&utm_source=openai&y=2')).to eq('https://exemplo.com/a?x=1&y=2')
    expect(limpar('https://exemplo.com/a?utm_source=openai&y=2')).to eq('https://exemplo.com/a?y=2')
    expect(limpar('https://exemplo.com/a?y=2&utm_source=openai')).to eq('https://exemplo.com/a?y=2')
  end

  it 'transforma o link em markdown no endereço puro e limpo' do
    texto = 'Fonte: [Clima em Bariloche](https://exemplo.com/clima?utm_source=openai) e [outro](https://outro.com/x?a=1&utm_source=openai).'

    expect(limpar(texto)).to eq('Fonte: https://exemplo.com/clima e https://outro.com/x?a=1.')
  end

  it 'pula o link em markdown incompleto e o colchete solto de outra linha, sem engolir texto', :aggregate_failures do
    expect(limpar('veja a](https://a.com/x) e [b](https://b.com/y?utm_source=openai)'))
      .to eq('veja a](https://a.com/x) e https://b.com/y')
    expect(limpar("[nota] texto\nFonte](https://b.com/y?utm_source=openai)")).to eq("[nota] texto\nFonte](https://b.com/y)")
  end

  it 'não leva a pontuação do texto para dentro da URL', :aggregate_failures do
    expect(limpar('(https://exemplo.com/a?utm_source=openai)')).to eq('(https://exemplo.com/a)')
    expect(limpar('Acesse https://exemplo.com/a?utm_source=openai.')).to eq('Acesse https://exemplo.com/a.')
  end

  it 'deixa intacto o texto sem URL', :aggregate_failures do
    expect(limpar('Olá, tudo bem? utm_source=openai fica.')).to eq('Olá, tudo bem? utm_source=openai fica.')
    expect(limpar(nil)).to be_nil
  end

  it 'deixa intacta a URL sem a marca e a de outro utm_source', :aggregate_failures do
    expect(limpar('https://exemplo.com/a?x=1')).to eq('https://exemplo.com/a?x=1')
    expect(limpar('https://exemplo.com/a?utm_source=newsletter&x=1')).to eq('https://exemplo.com/a?utm_source=newsletter&x=1')
    expect(limpar('https://exemplo.com/a?utm_source=openai_x')).to eq('https://exemplo.com/a?utm_source=openai_x')
  end
end
