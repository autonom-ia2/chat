require 'rails_helper'

# #2296: sem o anúncio de origem (Crm::AnuncioDeOrigem.ve?), o painel sai sem a lista de anúncios, sem o anuncio_id das
# procuras e sem as sugestões da frente "anúncio" (escritas fora, falam do anúncio). As contagens e as outras frentes ficam.
RSpec.describe Autonomia::Desempenho::Visibilidade do
  let(:painel) do
    {
      'meta' => { 'visibilidade' => { 'escopo' => 'conta' } }, 'ticket' => nil,
      'origem' => { 'anuncios_ligados' => true, 'anuncios' => [{ 'id' => '1202000999', 'nome' => 'Carrossel Primavera' }],
                    'comparacao' => { 'anuncio' => { 'procuras' => 3 }, 'sem_anuncio' => { 'procuras' => 5 } } },
      'procuras' => [{ 'conversa' => 1, 'anuncio_id' => '1202000999' }],
      'recomendacoes' => [{ 'frente' => 'anuncio', 'titulo' => 'Pausar o Carrossel Primavera' },
                          { 'frente' => 'equipe', 'titulo' => 'Responder mais rápido' }]
    }
  end

  it 'sem a chave: tira os anúncios, o anuncio_id e a sugestão da frente anúncio; ficam as contagens' do
    aplicado = described_class.new(ocultas: nil, ve_anuncio: false).aplicar(painel)

    expect(aplicado['origem']).to include('anuncios' => [], 'anuncios_ocultos' => true,
                                          'comparacao' => painel['origem']['comparacao'])
    expect(aplicado['procuras']).to eq([{ 'conversa' => 1, 'anuncio_id' => nil }])
    expect(aplicado['recomendacoes'].pluck('frente')).to eq(['equipe'])
    expect(aplicado.to_json).not_to include('1202000999', 'Carrossel Primavera')
  end

  it 'com a chave: o painel fica como veio' do
    expect(described_class.new(ocultas: nil, ve_anuncio: true).aplicar(painel)).to eq(painel)
  end
end
