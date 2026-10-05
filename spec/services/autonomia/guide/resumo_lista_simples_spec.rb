require 'rails_helper'

# A resposta de "adicionar etiqueta" é uma lista de textos. Resumir quebrava depois de a ação valer
# (TL03 com o Jev de verdade, 04/10): o Guia dizia que nada tinha mudado, e a conversa estava etiquetada.
RSpec.describe Autonomia::Guide::Resumo do
  it 'devolve a lista de valores simples como veio' do
    expect(described_class.new(corpo: { payload: %w[sinistro vip] }.to_json).texto).to include('["sinistro","vip"]')
  end

  it 'lista de objetos continua resumida com o catálogo de campos' do
    texto = described_class.new(corpo: [{ id: 1, name: 'Ana' }].to_json).texto

    expect(texto).to include('"name":"Ana"').and include('campos')
  end
end
