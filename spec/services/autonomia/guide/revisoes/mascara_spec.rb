require 'rails_helper'

# E-mail e telefone saem do texto antes da IA ler a conversa (#3158, B8b), sem expressão regular.
RSpec.describe Autonomia::Guide::Revisoes::Mascara do
  subject(:mascara) { described_class.new(literais: ['ana@exemplo.com.br', '+5511987654321']) }

  it 'troca e-mail e telefone escritos no meio da frase', :aggregate_failures do
    texto = 'Me chama no (11) 98765-4321 ou escreve para joao.silva@empresa.com, obrigado!'

    expect(mascara.call(texto)).to eq('Me chama no (11) [telefone] ou escreve para [e-mail] obrigado!')
  end

  it 'troca o e-mail e o telefone do contato mesmo colados em outra palavra' do
    expect(mascara.call('contato:ana@exemplo.com.br/+5511987654321')).to eq('contato:[e-mail]/[telefone]')
  end

  it 'mantém número curto, data e valor', :aggregate_failures do
    expect(mascara.call('Pedido 4521 de 17/11/2026 custou R$ 1.299,90')).to eq('Pedido 4521 de 17/11/2026 custou R$ 1.299,90')
    expect(mascara.call('arroba @ sozinha')).to eq('arroba @ sozinha')
  end
end
