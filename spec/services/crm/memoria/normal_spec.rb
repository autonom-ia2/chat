require 'rails_helper'

RSpec.describe Crm::Memoria::Normal do
  it 'documento: contido no texto normalizado, com pontuação ou espaço no meio' do
    expect(described_class.contido?('123.456.789-09', ['cpf:12345678909'])).to be(true)
    expect(described_class.contido?('ABC1D23', ['placa abc 1d23'])).to be(true)
  end

  it 'valor curto: só palavra inteira ou palavras vizinhas juntas, nunca dentro de outra' do
    expect(described_class.contido?('SP', ['moro em SP'])).to be(true)
    expect(described_class.contido?('2002', ['ano 12002'])).to be(false)
    expect(described_class.contido?('2002', ['ano 20 02'])).to be(true)
    expect(described_class.contido?('sim', ['simples'])).to be(false)
  end
end
