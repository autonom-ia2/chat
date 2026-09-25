require 'rails_helper'

# Motor dos filtros avançados (#677, frente B) com a resposta do Google Places passando pelo provider de verdade.
# O mock_provider não serve de prova: foi com ele que has_photos e open_now pareciam funcionar e zeravam a busca real.
#
# A fixture tem 8 lugares no formato da Places API (New) searchText, na ordem do Google (posição 1 a 8):
#   fotos:              A B E F H têm; C D G não têm
#   aberto agora:       A C G H openNow=true; B F openNow=false; D E sem currentOpeningHours
#   horário cadastrado: A B C F G H têm regularOpeningHours; D E não têm
#   nota:               A 4.7, B 4.2, C 3.9, D sem nota, E 4.5, F 4.8, G 5.0, H 4.4
#
# has_photos, open_now e has_opening_hours vêm do provider (contrato #677: o dono é a frente C).
RSpec.describe Autonomia::Prospecting::SearchRunner do
  around { |example| with_modified_env('GOOGLE_PLACES_API_KEY' => 'chave-da-plataforma') { example.run } }

  let(:account) { create(:account) }
  let(:user) { create(:user, :administrator, account: account) }
  let(:google_endpoint) { Autonomia::Prospecting::Providers::GooglePlacesProvider::ENDPOINT }

  before do
    Autonomia::Prospecting::Setting.for_account(account).update!(provider: 'google_places')
    stub_request(:post, google_endpoint)
      .to_return(status: 200, body: file_fixture('google_places/search_text_filtros.json').read,
                 headers: { 'Content-Type' => 'application/json' })
  end

  def names_with(advanced_filters)
    described_class.new(
      account: account,
      user: user,
      params: { query: 'padaria', location: 'Curitiba, PR', requested_limit: 8, advanced_filters: advanced_filters }
    ).perform.leads.map(&:name)
  end

  def exemplos(*letras)
    letras.map { |letra| "Padaria Exemplo #{letra}" }
  end

  it 'sem filtro devolve os 8 lugares' do
    expect(names_with({}).size).to eq(8)
  end

  describe 'fotos' do
    it 'has_photos yes mantém só os 5 com foto' do
      expect(names_with(has_photos: 'yes')).to eq(exemplos('A', 'B', 'E', 'F', 'H'))
    end

    it 'has_photos no mantém só os 3 sem foto' do
      expect(names_with(has_photos: 'no')).to eq(exemplos('C', 'D', 'G'))
    end
  end

  describe 'aberto agora' do
    it 'open_now yes mantém só os 4 com openNow=true' do
      expect(names_with(open_now: 'yes')).to eq(exemplos('A', 'C', 'G', 'H'))
    end

    # Como no Orth, "aberto agora" só tem a opção sim. Um valor diferente (busca salva antes desta mudança) não filtra.
    it 'open_now no não filtra' do
      expect(names_with(open_now: 'no').size).to eq(8)
    end
  end

  describe 'tem horário' do
    it 'has_opening_hours yes mantém só os 6 com horário cadastrado' do
      expect(names_with(has_opening_hours: 'yes')).to eq(exemplos('A', 'B', 'C', 'F', 'G', 'H'))
    end
  end

  describe 'avaliação com operador' do
    it 'acima de (rating_min) descarta quem está abaixo e quem não tem nota' do
      expect(names_with(rating_min: '4.5')).to eq(exemplos('A', 'E', 'F', 'G'))
    end

    it 'abaixo de (rating_max) descarta quem está acima e deixa passar quem não tem nota, como no Orth' do
      expect(names_with(rating_max: '4.4')).to eq(exemplos('B', 'C', 'D', 'H'))
    end
  end

  describe 'faixa de posição no Google' do
    it 'outside_top descarta as N primeiras posições' do
      expect(names_with(outside_top: '5')).to eq(exemplos('F', 'G', 'H'))
    end

    it 'outside_top com search_rank_max fica só com a janela escolhida' do
      expect(names_with(outside_top: '3', search_rank_max: '6')).to eq(exemplos('D', 'E', 'F'))
    end

    # A faixa corta posições em qualquer raio. Contá-las como falta fazia a busca expandir até 4x e pagar 3 chamadas.
    context 'with auto_expand_radius (expandir raio automaticamente)' do
      def expanded_search(requested_limit: 8, **advanced_filters)
        described_class.new(
          account: account,
          user: user,
          params: { query: 'padaria', location: 'Curitiba, PR', radius: 1000, requested_limit: requested_limit,
                    filters: { auto_expand_radius: true }, advanced_filters: advanced_filters }
        ).perform.search
      end

      it 'não expande quando só a alça da esquerda tira posições e o pedido cabe no que sobra' do
        search = expanded_search(requested_limit: 6, outside_top: '2')

        expect(a_request(:post, google_endpoint)).to have_been_made.once
        expect(search.radius).to eq(1000)
        expect(search.metadata['radius_expanded']).to be(false)
        expect(search.metadata['results_count']).to eq(6)
      end

      # Com a paginação (#678) a busca alcança até a 60ª posição: pedir 8 fora do top 2 quando o Google só tem 8
      # lugares no raio é falta de lugar de verdade, e o raio cresce.
      it 'expande quando a alça da esquerda tira posições e o Google acaba antes do pedido' do
        search = expanded_search(outside_top: '2')

        expect(a_request(:post, google_endpoint)).to have_been_made.times(3)
        expect(search.radius).to eq(4000)
      end

      it 'não expande quando só a alça da direita tira posições' do
        search = expanded_search(search_rank_max: '5')

        expect(a_request(:post, google_endpoint)).to have_been_made.once
        expect(search.radius).to eq(1000)
        expect(search.metadata['results_count']).to eq(5)
      end

      it 'continua expandindo quando um filtro de atributo deixa a janela incompleta' do
        search = expanded_search(outside_top: '2', has_photos: 'yes')

        expect(a_request(:post, google_endpoint)).to have_been_made.times(3)
        expect(search.radius).to eq(4000)
      end
    end
  end

  # Sem o atributo, o filtro não tem como decidir. Antes ele descartava tudo em silêncio; agora a busca falha e aparece.
  it 'falha alto quando o provider não entrega o atributo que o filtro ativo precisa' do
    mock_provider_class = Autonomia::Prospecting::Providers::MockProvider
    Autonomia::Prospecting::Setting.for_account(account).update!(provider: 'mock')
    allow(mock_provider_class).to receive(:new)
      .and_return(instance_double(mock_provider_class, search: [{ provider: 'mock', name: 'Sem atributo', raw_payload: {} }]))

    expect { names_with(has_photos: 'yes') }.to raise_error(KeyError, /has_photos/)
  end

  it 'combina filtros de fontes diferentes' do
    expect(names_with(has_photos: 'yes', open_now: 'yes', rating_min: '4.5')).to eq(exemplos('A'))
  end
end
