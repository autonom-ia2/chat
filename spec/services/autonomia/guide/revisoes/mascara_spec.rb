require 'rails_helper'

# E-mail e telefone saem do texto antes da IA ler a conversa (#3158, B8b), sem expressão regular.
RSpec.describe Autonomia::Guide::Revisoes::Mascara do
  subject(:mascara) { described_class.new(literais: ['ana@exemplo.com.br', '+5511987654321']) }

  it 'troca e-mail e telefone escritos no meio da frase', :aggregate_failures do
    texto = 'Me chama no (11) 98765-4321 ou escreve para joao.silva@empresa.com, obrigado!'

    expect(mascara.call(texto)).to eq('Me chama no [telefone] ou escreve para [e-mail] obrigado!')
  end

  it 'troca o e-mail que fecha a frase com ponto' do
    expect(mascara.call('Meu e-mail é joao@empresa.com.br.')).to eq('Meu e-mail é [e-mail]')
  end

  it 'troca o telefone escrito em grupos separados por espaço', :aggregate_failures do
    expect(mascara.call('Liga 11 98765 4321 hoje')).to eq('Liga [telefone] hoje')
    expect(mascara.call('ou +55 11 98765-4321.')).to eq('ou [telefone]')
    expect(mascara.call('ou 1199 8765 4321')).to eq('ou [telefone]')
  end

  it 'não junta números curtos de uma lista' do
    expect(mascara.call('itens 1 2 3 e 10 20 30')).to eq('itens 1 2 3 e 10 20 30')
  end

  it 'aguenta byte inválido no texto' do
    expect(mascara.call("oi \xFF tudo bem")).to eq("oi \uFFFD tudo bem")
  end

  it 'troca o e-mail e o telefone do contato mesmo colados em outra palavra' do
    expect(mascara.call('contato:ana@exemplo.com.br/+5511987654321')).to eq('contato:[e-mail]/[telefone]')
  end

  it 'mantém número curto, data e valor', :aggregate_failures do
    expect(mascara.call('Pedido 4521 de 17/11/2026 custou R$ 1.299,90')).to eq('Pedido 4521 de 17/11/2026 custou R$ 1.299,90')
    expect(mascara.call('arroba @ sozinha')).to eq('arroba @ sozinha')
    expect(mascara.call('valor 1.500.000,00 pago')).to eq('valor 1.500.000,00 pago')
    expect(mascara.call('custou 1.500 2.000 3.000')).to eq('custou 1.500 2.000 3.000')
  end
end
