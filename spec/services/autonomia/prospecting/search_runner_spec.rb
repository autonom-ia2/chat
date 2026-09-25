require 'rails_helper'

RSpec.describe Autonomia::Prospecting::SearchRunner do
  let(:account) { create(:account) }
  let(:user) { create(:user, :administrator, account: account) }

  # O google_places virou o provider padrão (#683); estes testes exercitam o motor com o provider mock.
  before { Autonomia::Prospecting::Setting.for_account(account).update!(provider: 'mock') }

  it 'creates a completed search and persists mock leads' do
    result = described_class.new(
      account: account,
      user: user,
      params: { query: 'clinica odontologica', location: 'Curitiba, PR', requested_limit: 3 }
    ).perform

    expect(result.search).to be_completed
    expect(result.search.query).to eq('clinica odontologica')
    expect(result.leads.size).to eq(3)
    expect(account.autonomia_prospecting_leads.count).to eq(3)
    expect(result.search.metadata['lead_ids']).to match_array(result.leads.map(&:id))
  end

  it 'stores location metadata in the saved search' do
    result = described_class.new(
      account: account,
      user: user,
      params: {
        query: 'restaurante',
        location: 'Divinopolis, MG',
        requested_limit: 1,
        metadata: {
          'location_place_id' => 'places/divinopolis',
          'location_latitude' => -20.1446,
          'location_longitude' => -44.8912,
          'location_label' => 'Divinopolis, MG, Brasil'
        }
      }
    ).perform

    expect(result.search.metadata).to include(
      'location_place_id' => 'places/divinopolis',
      'location_latitude' => -20.1446,
      'location_longitude' => -44.8912,
      'location_label' => 'Divinopolis, MG, Brasil'
    )
  end

  it 'deduplicates leads inside the same account' do
    params = { query: 'restaurante', location: 'Sao Paulo, SP', requested_limit: 2 }

    described_class.new(account: account, user: user, params: params).perform
    second_result = described_class.new(account: account, user: user, params: params).perform

    expect(second_result.leads.size).to eq(2)
    expect(account.autonomia_prospecting_leads.count).to eq(2)
    expect(second_result.search.metadata['lead_ids']).to match_array(second_result.leads.map(&:id))
  end

  it 'keeps dedupe scoped to account' do
    params = { query: 'academia', location: 'Rio de Janeiro, RJ', requested_limit: 1 }
    other_account = create(:account)
    other_user = create(:user, :administrator, account: other_account)
    Autonomia::Prospecting::Setting.for_account(other_account).update!(provider: 'mock')

    described_class.new(account: account, user: user, params: params).perform
    described_class.new(account: other_account, user: other_user, params: params).perform

    expect(account.autonomia_prospecting_leads.count).to eq(1)
    expect(other_account.autonomia_prospecting_leads.count).to eq(1)
  end

  it 'ignores max_results_per_search from the account' do
    Autonomia::Prospecting::Setting.for_account(account).update!(max_results_per_search: 2)

    result = described_class.new(
      account: account,
      user: user,
      params: { query: 'hotel', location: 'Sao Paulo, SP', requested_limit: 3 }
    ).perform

    expect(result.leads.size).to eq(3)
  end

  it 'rejects google places when the platform key is missing, even with a key saved on the account' do
    Autonomia::Prospecting::Setting.for_account(account).update!(provider: 'google_places', google_places_api_key: 'chave-da-conta')

    expect do
      with_modified_env('GOOGLE_PLACES_API_KEY' => nil) do
        described_class.new(
          account: account,
          user: user,
          params: { query: 'hotel', location: 'Sao Paulo, SP', requested_limit: 1 }
        ).perform
      end
    end.to raise_error(Autonomia::Prospecting::SearchRunner::ProviderError, 'A busca no Google está indisponível no momento. Fale com o suporte.')
  end

  # A chave da plataforma vem só do ambiente (#683): uma InstallationConfig homônima apareceria no superadmin.
  it 'ignores an InstallationConfig with the platform key name: the key comes only from the environment' do
    InstallationConfig.where(name: 'GOOGLE_PLACES_API_KEY').first_or_create!(value: 'chave-no-banco')
    Autonomia::Prospecting::Setting.for_account(account).update!(provider: 'google_places')

    expect do
      with_modified_env('GOOGLE_PLACES_API_KEY' => nil) do
        described_class.new(
          account: account,
          user: user,
          params: { query: 'hotel', location: 'Sao Paulo, SP', requested_limit: 1 }
        ).perform
      end
    end.to raise_error(Autonomia::Prospecting::SearchRunner::ProviderError, 'A busca no Google está indisponível no momento. Fale com o suporte.')
  end

  it 'stores the default CRM target in new searches' do
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    Autonomia::Prospecting::Setting.for_account(account).update!(
      default_crm_pipeline: pipeline,
      default_crm_stage: stage
    )

    result = described_class.new(
      account: account,
      user: user,
      params: { query: 'clinica', location: 'Curitiba, PR', requested_limit: 1 }
    ).perform

    expect(result.search.metadata['crm_pipeline_id']).to eq(pipeline.id)
    expect(result.search.metadata['crm_stage_id']).to eq(stage.id)
  end

  it 'uses cache for repeated searches with the same fingerprint' do
    Autonomia::Prospecting::Setting.for_account(account).update!(cache_ttl_seconds: 3600)
    params = { query: 'padaria', location: 'Sao Paulo, SP', requested_limit: 1 }

    first = described_class.new(account: account, user: user, params: params).perform
    second = described_class.new(account: account, user: user, params: params).perform

    expect(first.search).to be_completed
    expect(second.search).to be_cached
    expect(second.leads.map(&:id)).to eq(first.leads.map(&:id))
    expect(second.search.consumed_api_units).to eq(0)
  end

  # Caracterização do motor (#683). Os casos que eram DIVERGE e a E0 corrigiu
  # foram invertidos para o comportamento novo; o DIVERGE que resta é de outra etapa.
  describe 'caracterização do motor (#683)' do
    around { |example| with_modified_env('GOOGLE_PLACES_API_KEY' => 'chave-da-plataforma') { example.run } }

    let(:setting) { Autonomia::Prospecting::Setting.for_account(account) }
    let(:mock_provider_class) { Autonomia::Prospecting::Providers::MockProvider }
    let(:google_endpoint) { Autonomia::Prospecting::Providers::GooglePlacesProvider::ENDPOINT }
    let(:places) do
      [
        { provider: 'mock', provider_place_id: 'places/a', name: 'Alfa Odonto', phone: '+5541999990001',
          website: 'https://alfa.example.com', rating: 4.8, reviews_count: 120, raw_payload: {} },
        { provider: 'mock', provider_place_id: 'places/b', name: 'Beta Odonto', phone: nil,
          website: nil, rating: 3.9, reviews_count: 5, raw_payload: {} },
        { provider: 'mock', provider_place_id: 'places/c', name: 'Gama Odonto', phone: '+5541999990003',
          website: 'https://gama.example.com', rating: nil, reviews_count: 40, raw_payload: {} }
      ]
    end
    let(:google_place) do
      {
        'id' => 'places/google-1',
        'displayName' => { 'text' => 'Clinica Aberta' },
        'formattedAddress' => 'Rua A, 10 - Centro, Curitiba - PR, Brasil',
        'internationalPhoneNumber' => '+55 41 3333-0000',
        'websiteUri' => 'https://clinicaaberta.example.com',
        'rating' => 4.7,
        'userRatingCount' => 80,
        'types' => ['dentist'],
        'photos' => [{ 'name' => 'places/google-1/photos/1' }],
        'currentOpeningHours' => { 'openNow' => true }
      }
    end

    def run_search(params)
      described_class.new(account: account, user: user, params: params).perform
    end

    def stub_mock_provider(results)
      allow(mock_provider_class).to receive(:new).and_return(instance_double(mock_provider_class, search: results))
    end

    def stub_google_places(places_payload, api_key: 'chave-da-plataforma')
      stub_request(:post, google_endpoint)
        .with(headers: { 'X-Goog-Api-Key' => api_key })
        .to_return(status: 200, body: { places: places_payload }.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    # A chave da plataforma vem do ambiente (around no topo deste describe); aqui só a conta passa para o Google.
    def use_google_places!(**extra)
      setting.update!(provider: 'google_places', **extra)
    end

    describe 'provider padrão' do
      it 'cria a configuração de conta nova com google_places' do
        expect(Autonomia::Prospecting::Setting.for_account(create(:account)).provider).to eq('google_places')
      end

      it 'busca no Google com provider_enabled desligado na conta quando a chave de plataforma existe' do
        use_google_places!(provider_enabled: false)
        stub_google_places([google_place])

        expect(run_search(query: 'hotel', location: 'Curitiba, PR', requested_limit: 1).search).to be_completed
      end

      it 'chama o Google Places com a chave da plataforma, não com a gravada na conta' do
        use_google_places!(google_places_api_key: 'chave-da-conta')
        stub_google_places([google_place])

        result = run_search(query: 'clinica', location: 'Curitiba, PR', requested_limit: 1)

        expect(result.search).to be_completed
        expect(result.search.consumed_api_units).to eq(1)
        expect(result.leads.map(&:provider_place_id)).to eq(['places/google-1'])
        expect(a_request(:post, google_endpoint).with(headers: { 'X-Goog-Api-Key' => 'chave-da-plataforma' })).to have_been_made.once
        expect(a_request(:post, google_endpoint).with(headers: { 'X-Goog-Api-Key' => 'chave-da-conta' })).not_to have_been_made
      end
    end

    describe 'país e endereço (#677, E1 frente C)' do
      let(:google_place_with_address) do
        google_place.merge(
          'googleMapsUri' => 'https://maps.google.com/?cid=1',
          'regularOpeningHours' => { 'weekdayDescriptions' => ['segunda-feira: 08:00 – 18:00'] },
          'addressComponents' => [
            { 'longText' => 'Centro', 'shortText' => 'Centro', 'types' => %w[sublocality_level_1 sublocality] },
            { 'longText' => 'Curitiba', 'shortText' => 'Curitiba', 'types' => ['locality'] },
            { 'longText' => 'Paraná', 'shortText' => 'PR', 'types' => ['administrative_area_level_1'] },
            { 'longText' => 'Brasil', 'shortText' => 'BR', 'types' => ['country'] }
          ]
        )
      end

      it 'chama o Google com o país e o idioma da conta' do
        use_google_places!(search_country: 'PT')
        stub_google_places([google_place])

        run_search(query: 'clinica', location: 'Lisboa', requested_limit: 1)

        expect(
          a_request(:post, google_endpoint).with do |request|
            JSON.parse(request.body).slice('regionCode', 'languageCode') == { 'regionCode' => 'PT', 'languageCode' => 'pt-PT' }
          end
        ).to have_been_made.once
      end

      it 'grava endereço estruturado, link do Maps e sinais do lugar no lead' do
        use_google_places!
        stub_google_places([google_place_with_address])

        lead = run_search(query: 'clinica', location: 'Curitiba, PR', requested_limit: 1).leads.first.reload

        expect(
          lead.slice(:neighborhood, :city, :state, :country, :google_maps_uri, :has_photos, :photo_count, :open_now, :has_opening_hours)
        ).to eq(
          'neighborhood' => 'Centro', 'city' => 'Curitiba', 'state' => 'PR', 'country' => 'BR',
          'google_maps_uri' => 'https://maps.google.com/?cid=1', 'has_photos' => true, 'photo_count' => 1,
          'open_now' => true, 'has_opening_hours' => true
        )
      end

      it 'grava o país da conta no lead do provider mock' do
        setting.update!(search_country: 'MX')

        lead = run_search(query: 'dentista', location: 'Monterrey', requested_limit: 1).leads.first

        expect(lead.reload.country).to eq('MX')
      end

      it 'não reaproveita o cache de uma busca igual feita com outro país' do
        setting.update!(cache_ttl_seconds: 3600)
        params = { query: 'padaria', location: 'Centro', requested_limit: 1 }

        run_search(params)
        setting.update!(search_country: 'PT')
        second = run_search(params)

        expect(second.search).not_to be_cached
        expect(second.leads.first.reload.country).to eq('PT')
      end
    end

    describe 'filtros avançados' do
      it 'has_website yes mantém só quem tem site e no mantém só quem não tem' do
        stub_mock_provider(places)

        with_site = run_search(query: 'dentista', location: 'Curitiba, PR', requested_limit: 3,
                               advanced_filters: { has_website: 'yes' })
        without_site = run_search(query: 'dentista', location: 'Curitiba, PR', requested_limit: 3,
                                  advanced_filters: { has_website: 'no' })

        expect(with_site.leads.map(&:name)).to contain_exactly('Alfa Odonto', 'Gama Odonto')
        expect(without_site.leads.map(&:name)).to contain_exactly('Beta Odonto')
      end

      it 'has_phone yes mantém só quem tem telefone' do
        stub_mock_provider(places)

        result = run_search(query: 'dentista', location: 'Curitiba, PR', requested_limit: 3, advanced_filters: { has_phone: 'yes' })

        expect(result.leads.map(&:name)).to contain_exactly('Alfa Odonto', 'Gama Odonto')
      end

      it 'rating_min descarta quem está abaixo e quem não tem nota' do
        stub_mock_provider(places)

        result = run_search(query: 'dentista', location: 'Curitiba, PR', requested_limit: 3, advanced_filters: { rating_min: '4.0' })

        expect(result.leads.map(&:name)).to contain_exactly('Alfa Odonto')
      end

      it 'reviews_min e search_rank_max cortam por avaliações e posição no Google' do
        stub_mock_provider(places)

        by_reviews = run_search(query: 'dentista', location: 'Curitiba, PR', requested_limit: 3, advanced_filters: { reviews_min: '40' })
        by_rank = run_search(query: 'dentista', location: 'Curitiba, PR', requested_limit: 3, advanced_filters: { search_rank_max: '2' })

        expect(by_reviews.leads.map(&:name)).to contain_exactly('Alfa Odonto', 'Gama Odonto')
        expect(by_rank.leads.map(&:name)).to contain_exactly('Alfa Odonto', 'Beta Odonto')
      end

      # Os providers passaram a devolver has_photos e open_now (#677, E1 frente C): os filtros que zeravam tudo agora
      # separam quem tem de quem não tem. Com a paginação (#678) o filtro roda antes do corte: o mock segue gerando
      # lugares até completar os 8 com foto, em vez de entregar só os que tinham foto entre os 8 primeiros.
      it 'has_photos yes mantém só quem tem foto no payload do provider mock e completa o pedido' do
        params = { query: 'dentista', location: 'Curitiba, PR', radius: 1000, area_type: 'radius', area_config: {}, limit: 8 }
        with_photos = mock_provider_class.new(**params).search.count { |place| place.dig(:raw_payload, :photos).present? }
        expect(with_photos).to be_between(1, 7)

        result = run_search(query: 'dentista', location: 'Curitiba, PR', requested_limit: 8, advanced_filters: { has_photos: 'yes' })

        expect(result.leads.size).to eq(8)
        expect(result.leads.map(&:has_photos)).to all(be(true))
      end

      it 'has_photos no mantém só quem não tem foto' do
        result = run_search(query: 'dentista', location: 'Curitiba, PR', requested_limit: 8, advanced_filters: { has_photos: 'no' })

        expect(result.leads).to be_present
        expect(result.leads.map(&:has_photos)).to all(be(false))
      end

      # Como no Orth, aberto agora só tem a opção "sim" (frente B): outro valor não filtra.
      it 'open_now yes mantém só abertos e no não filtra' do
        yes_result = run_search(query: 'dentista', location: 'Curitiba, PR', requested_limit: 8, advanced_filters: { open_now: 'yes' })
        no_result = run_search(query: 'dentista', location: 'Curitiba, PR', requested_limit: 8, advanced_filters: { open_now: 'no' })

        expect(yes_result.leads.map(&:open_now)).to be_present.and all(be(true))
        expect(no_result.leads.map(&:open_now)).to include(true, false)
      end

      it 'no Google Places, has_photos yes e open_now yes mantêm um lugar aberto e com foto' do
        use_google_places!
        stub_google_places([google_place])

        with_photos = run_search(query: 'clinica', location: 'Curitiba, PR', requested_limit: 1, advanced_filters: { has_photos: 'yes' })
        open_now = run_search(query: 'clinica', location: 'Curitiba, PR', requested_limit: 1, advanced_filters: { open_now: 'yes' })

        expect(with_photos.leads.map(&:provider_place_id)).to eq(['places/google-1'])
        expect(open_now.leads.map(&:provider_place_id)).to eq(['places/google-1'])
      end
    end

    describe 'limite pedido' do
      it 'usa o default_limit da conta quando o pedido não traz limite' do
        result = run_search(query: 'padaria', location: 'Curitiba, PR')

        expect(result.search.requested_limit).to eq(20)
        expect(result.leads.size).to eq(20)
      end

      it 'aceita limit como sinônimo de requested_limit' do
        result = run_search(query: 'padaria', location: 'Curitiba, PR', limit: 2)

        expect(result.search.requested_limit).to eq(2)
      end

      it 'recusa limite zero' do
        expect { run_search(query: 'padaria', location: 'Curitiba, PR', requested_limit: 0) }
          .to raise_error(ActiveRecord::RecordInvalid) { |error|
            expect(error.record.errors[:base]).to eq([I18n.t('autonomia.prospecting.errors.limit_invalid')])
          }
      end

      it 'aceita 21 e 60 com o max_results_per_search padrão de 20 e recusa 61' do
        expect(setting.max_results_per_search).to eq(20)

        expect(run_search(query: 'padaria', location: 'Curitiba, PR', requested_limit: 21).leads.size).to eq(21)
        expect(run_search(query: 'padaria', location: 'Curitiba, PR', requested_limit: 60).leads.size).to eq(60)
        expect { run_search(query: 'padaria', location: 'Curitiba, PR', requested_limit: 61) }
          .to raise_error(ActiveRecord::RecordInvalid) { |error|
            expect(error.record.errors[:base]).to eq([I18n.t('autonomia.prospecting.errors.limit_too_high', max: 60)])
          }
      end

      # Com a paginação (#678) a página é sempre de 20 (pageSize) e o pedido de 60 chega em até 3 páginas.
      it 'pede páginas de 20 ao Google Places e para quando o Google não manda token' do
        use_google_places!
        stub_google_places([google_place])

        run_search(query: 'clinica', location: 'Curitiba, PR', requested_limit: 60)

        expect(a_request(:post, google_endpoint).with { |req| JSON.parse(req.body)['pageSize'] == 20 }).to have_been_made.once
      end

      it 'não expande o raio num pedido de 60 quando as três páginas do primeiro raio trazem os 60' do
        use_google_places!
        pages = Array.new(3) do |page|
          { 'places' => Array.new(20) { |index| google_place.merge('id' => "places/google-#{page}-#{index}") },
            'nextPageToken' => (page < 2 ? "token-#{page + 1}" : nil) }.compact
        end
        stub_request(:post, google_endpoint).to_return do |request|
          token = JSON.parse(request.body)['pageToken']
          { status: 200, body: pages[token.to_s.delete_prefix('token-').to_i].to_json, headers: { 'Content-Type' => 'application/json' } }
        end

        result = run_search(query: 'clinica', location: 'Curitiba, PR', requested_limit: 60, radius: 1000,
                            filters: { auto_expand_radius: true })

        expect(a_request(:post, google_endpoint)).to have_been_made.times(3)
        expect(result.search.consumed_api_units).to eq(3)
        expect(result.search.radius).to eq(1000)
        expect(result.search.metadata['radius_expanded']).to be(false)
        expect(result.leads.size).to eq(60)
      end

      # Antes o Google entregava no máximo 20 e o raio nunca crescia por isso (#683). Com a paginação, faltar lugar
      # depois de o Google parar de mandar token é falta de verdade, e o raio cresce (#678). Desde o #732, uma
      # tentativa com o dobro, que só fica se trouxer mais.
      it 'expande o raio quando o Google acaba antes de completar o pedido' do
        use_google_places!
        stub_request(:post, google_endpoint).to_return do |request|
          count = JSON.parse(request.body).dig('locationBias', 'circle', 'radius') == 1000 ? 20 : 25
          places = Array.new(count) { |index| google_place.merge('id' => "places/google-#{index}") }
          { status: 200, body: { places: places }.to_json, headers: { 'Content-Type' => 'application/json' } }
        end

        result = run_search(query: 'clinica', location: 'Curitiba, PR', requested_limit: 60, radius: 1000,
                            metadata: { location_latitude: -25.43, location_longitude: -49.27 },
                            filters: { auto_expand_radius: true })

        expect(a_request(:post, google_endpoint)).to have_been_made.times(2)
        expect(result.search.radius).to eq(2000)
      end
    end

    describe 'limites de consumo' do
      before do
        use_google_places!
        stub_google_places([google_place])
      end

      it 'segue com o monthly_limit do mês já consumido' do
        setting.update!(monthly_limit: 2)
        Autonomia::Prospecting::Search.create!(account: account, user: user, query: 'padaria', requested_limit: 1, consumed_api_units: 2)

        expect(run_search(query: 'hotel', location: 'Curitiba, PR', requested_limit: 1).search).to be_completed
      end

      it 'segue com o daily_limit estourado e a expansão automática de raio ligada' do
        setting.update!(daily_limit: 1)
        Autonomia::Prospecting::Search.create!(account: account, user: user, query: 'padaria', requested_limit: 1, consumed_api_units: 1)

        result = run_search(query: 'hotel', location: 'Curitiba, PR', requested_limit: 2, filters: { auto_expand_radius: true },
                            metadata: { location_latitude: -25.43, location_longitude: -49.27 })

        expect(result.search).to be_completed
        expect(result.search.consumed_api_units).to eq(2)
      end

      it 'não trava o provider mock, que não consome unidade' do
        setting.update!(provider: 'mock', daily_limit: 1, monthly_limit: 1)
        Autonomia::Prospecting::Search.create!(account: account, user: user, query: 'padaria', requested_limit: 1, consumed_api_units: 5)

        expect(run_search(query: 'hotel', location: 'Curitiba, PR', requested_limit: 1).search).to be_completed
      end

      it 'serve do cache sem chamar o Google de novo' do
        setting.update!(daily_limit: 1, cache_ttl_seconds: 3600)
        params = { query: 'clinica', location: 'Curitiba, PR', requested_limit: 1 }

        first = run_search(params)
        second = run_search(params)

        expect(first.search).to be_completed
        expect(second.search).to be_cached
        expect(a_request(:post, google_endpoint)).to have_been_made.once
      end
    end

    describe 'cache' do
      let(:params) { { query: 'padaria', location: 'Curitiba, PR', requested_limit: 2 } }

      it 'está ligado por padrão, com validade de 24 horas' do
        expect(setting.cache_ttl_seconds).to eq(86_400)

        first = run_search(params)
        second = run_search(params)

        expect(second.search).to be_cached
        expect(second.search.metadata['cached_from_search_id']).to eq(first.search.id)
      end

      it 'não usa cache com cache_ttl_seconds zero' do
        setting.update!(cache_ttl_seconds: 0)

        run_search(params)
        second = run_search(params)

        expect(second.search).to be_completed
        expect(second.search.cache_expires_at).to be_nil
      end

      it 'não serve uma busca que falhou como cache: a repetição roda o provider de novo' do
        failing_provider = instance_double(mock_provider_class)
        allow(failing_provider).to receive(:search).and_raise(StandardError, 'provider fora do ar')
        allow(mock_provider_class).to receive(:new).and_return(failing_provider)

        expect { run_search(params) }.to raise_error(StandardError, 'provider fora do ar')
        failed_search = account.autonomia_prospecting_searches.order(:id).last
        expect(failed_search).to be_failed
        expect(failed_search.metadata['error']).to eq('provider fora do ar')

        allow(mock_provider_class).to receive(:new).and_call_original
        second = run_search(params)

        expect(second.search).to be_completed
        expect(second.search.metadata).not_to have_key('cached_from_search_id')
        expect(second.leads.size).to eq(2)
      end
    end

    describe 'upsert do lead' do
      it 'atualiza o lead do mesmo lugar, move para a busca nova e preserva o metadata antigo' do
        stub_mock_provider([places.first])
        first = run_search(query: 'dentista', location: 'Curitiba, PR', requested_limit: 1)
        lead = first.leads.first
        lead.update!(metadata: lead.metadata.merge('whatsapp_verification' => { 'status' => 'verified' }))

        stub_mock_provider([places.first.merge(name: 'Alfa Odonto Renovada')])
        second = run_search(query: 'dentista sorriso', location: 'Curitiba, PR', requested_limit: 1)

        expect(account.autonomia_prospecting_leads.count).to eq(1)
        expect(lead.reload.name).to eq('Alfa Odonto Renovada')
        expect(lead.prospect_search_id).to eq(second.search.id)
        expect(lead.metadata.dig('whatsapp_verification', 'status')).to eq('verified')
      end

      # ENRIQ-69 (#682, E6): a verificação é do número verificado, não do lead. Busca nova com outro telefone
      # deixa a do número antigo sem valer e o lead volta à fila de verificação.
      context 'when a busca nova traz outro telefone para o lead' do
        include ActiveJob::TestHelper

        let(:old_verification) do
          { 'status' => 'verified', 'phone' => '+5541999990001', 'chat_id' => '5541999990001@c.us' }
        end
        let(:site_verification) { { 'status' => 'not_whatsapp', 'phone' => '+5541977776666' } }

        def search_with_phone(phone)
          stub_mock_provider([places.first.merge(phone: phone)])
          run_search(query: 'dentista', location: 'Curitiba, PR', requested_limit: 1, fresh: true)
        end

        def verified_lead
          lead = search_with_phone('+5541999990001').leads.first
          lead.update!(metadata: lead.metadata.merge('whatsapp_verification' => old_verification,
                                                     'site_whatsapp_verification' => site_verification))
          lead
        end

        it 'deixa a verificação do número antigo sem valer e o botão sem o número antigo' do
          lead = verified_lead

          second = search_with_phone('+55 41 98888-7777')

          expect(lead.reload.phone).to eq('+55 41 98888-7777')
          expect(lead.metadata).not_to have_key('whatsapp_verification')
          expect(lead.metadata['site_whatsapp_verification']).to eq(site_verification)
          expect(second.leads.first.metadata).not_to have_key('whatsapp_verification')
          payload = Autonomia::Prospecting::LeadPayload.new(account: account).build(lead)
          expect(payload).to include(whatsapp_verified: false, whatsapp_phone: '+5541988887777')
        end

        it 'põe o lead de novo na fila de verificação da E2' do
          lead = verified_lead
          Autonomia::Prospecting::Config.enable_for!(account)
          create(:channel_api, account: account, additional_attributes: { 'provider' => 'waha', 'session' => 'sessao-prospeccao' })

          second = search_with_phone('+55 41 98888-7777')
          with_modified_env('WAHA_API_URL' => 'https://waha.test', 'WAHA_API_KEY' => 'chave-waha-teste') do
            Autonomia::Prospecting::LeadWorkQueue.after_search(account: account, leads: second.leads)
          end

          expect(Autonomia::Prospecting::VerifyWhatsappJob).to have_been_enqueued.with(account.id, [lead.id])
          expect(lead.reload.metadata.dig('whatsapp_verification', 'status')).to eq('queued')
        end

        # A decisão é do banco, na hora de gravar: uma verificação do número antigo que termina depois de a busca ler
        # o lead também sai.
        it 'tira a verificação do número antigo gravada entre a leitura do lead e a gravação' do
          lead = search_with_phone('+5541999990001').leads.first
          stub_mock_provider([places.first.merge(phone: '+55 41 98888-7777')])
          runner = described_class.new(account: account, user: user,
                                       params: { query: 'dentista', location: 'Curitiba, PR', requested_limit: 1, fresh: true })
          allow(runner).to receive(:score_for).and_wrap_original do |original, *args, **kwargs|
            Autonomia::Prospecting::Lead.where(id: lead.id).update_all( # rubocop:disable Rails/SkipsModelValidations
              ['metadata = metadata || ?::jsonb', { 'whatsapp_verification' => old_verification }.to_json]
            )
            original.call(*args, **kwargs)
          end

          runner.perform

          expect(lead.reload.phone).to eq('+55 41 98888-7777')
          expect(lead.metadata).not_to have_key('whatsapp_verification')
        end

        it 'mantém a verificação quando o telefone é o mesmo, só escrito de outro jeito' do
          lead = verified_lead

          search_with_phone('(41) 99999-0001')

          expect(lead.reload.metadata['whatsapp_verification']).to eq(old_verification)
        end
      end

      # ENRIQ-57 (#682, E6): a busca grava só as chaves que traz no metadata, sem regravar o que leu antes. Uma
      # verificação que termina entre a leitura e a gravação do lead não some.
      it 'não apaga a verificação gravada em paralelo durante o upsert' do
        stub_mock_provider([places.first])
        lead = run_search(query: 'dentista', location: 'Curitiba, PR', requested_limit: 1).leads.first
        verification = { 'status' => 'verified', 'phone' => '+5541999990001' }
        # O Google traz as avaliações no metadata do lead; é essa gravação que regravava o jsonb inteiro.
        stub_mock_provider([places.first.merge(metadata: { reviews_snapshot: [{ 'text' => 'Atendimento ótimo' }] })])
        runner = described_class.new(account: account, user: user,
                                     params: { query: 'dentista', location: 'Curitiba, PR', requested_limit: 1, fresh: true })
        allow(runner).to receive(:score_for).and_wrap_original do |original, *args, **kwargs|
          Autonomia::Prospecting::Lead.where(id: lead.id).update_all( # rubocop:disable Rails/SkipsModelValidations
            ['metadata = metadata || ?::jsonb', { 'whatsapp_verification' => verification }.to_json]
          )
          original.call(*args, **kwargs)
        end

        runner.perform

        expect(lead.reload.metadata['whatsapp_verification']).to eq(verification)
      end

      it 'deduplica pelo telefone quando o lugar não tem provider_place_id' do
        stub_mock_provider([places.first.merge(provider_place_id: nil)])

        result = run_search(query: 'dentista', location: 'Curitiba, PR', requested_limit: 1)

        expect(result.leads.first.dedupe_key).to eq('mock:+5541999990001')
      end

      it 'reaproveita o lead quando outra busca grava o mesmo lugar entre a leitura e o insert' do
        stub_mock_provider([places.first])
        competitor_saved = false
        allow(Autonomia::Prospecting::Lead).to receive(:new).and_wrap_original do |original, *args, &block|
          unless competitor_saved
            competitor_saved = true
            original.call(account: account, provider: 'mock', provider_place_id: 'places/a', name: 'Gravado pela outra busca').save!
          end
          original.call(*args, &block)
        end

        result = run_search(query: 'dentista', location: 'Curitiba, PR', requested_limit: 1)

        expect(result.search).to be_completed
        expect(account.autonomia_prospecting_leads.count).to eq(1)
        expect(result.leads.first.name).to eq('Alfa Odonto')
        expect(result.leads.first.prospect_search_id).to eq(result.search.id)
      end

      it 'reaproveita o lead quando o banco recusa o insert pelo índice único (corrida real)' do
        stub_mock_provider([places.first])
        competitor_saved = false
        # A outra busca grava depois da validação desta: o INSERT de verdade bate no índice único do Postgres.
        # O lead é criado dentro do runner, então só any_instance alcança o save! dele; o insert_all! é a outra busca.
        # rubocop:disable RSpec/AnyInstance, Rails/SkipsModelValidations
        allow_any_instance_of(Autonomia::Prospecting::Lead).to receive(:save!).and_wrap_original do |original, *args|
          next original.call(*args) if competitor_saved

          competitor_saved = true
          Autonomia::Prospecting::Lead.insert_all!([{ account_id: account.id, provider: 'mock', provider_place_id: 'places/a',
                                                      dedupe_key: 'mock:places/a', name: 'Gravado pela outra busca',
                                                      created_at: Time.current, updated_at: Time.current }])
          original.call(validate: false)
        end
        # rubocop:enable RSpec/AnyInstance, Rails/SkipsModelValidations

        result = run_search(query: 'dentista', location: 'Curitiba, PR', requested_limit: 1)

        expect(result.search).to be_completed
        expect(account.autonomia_prospecting_leads.count).to eq(1)
        expect(result.leads.first.name).to eq('Alfa Odonto')
      end

      it 'não engole erro de validação que não é corrida' do
        stub_mock_provider([places.first.merge(name: nil)])

        expect { run_search(query: 'dentista', location: 'Curitiba, PR', requested_limit: 1) }
          .to raise_error(ActiveRecord::RecordInvalid, /Name can't be blank/)
      end
    end
  end

  # A prioridade conta o mesmo decisor que a tela mostra (#679): o da pesquisa. O nome gravado antes dela (palpite da IA
  # da E2) continua no lead, mas não sobe a prioridade.
  describe 'decisor na prioridade' do
    let(:runner) { described_class.new(account: account, user: user, params: { query: 'padaria' }) }

    def lead_with(decision_status:, decision_name:)
      Autonomia::Prospecting::Lead.new(account: account, provider: 'mock', provider_place_id: 'p1', name: 'Padaria', phone: '+554133330000',
                                       decision_name: decision_name, decision_research_status: decision_status)
    end

    it 'conta o decisor confirmado ou possível da pesquisa' do
      %w[confirmed possible].each do |status|
        expect(runner.send(:priority_multiplier, lead_with(decision_status: status, decision_name: 'ANA SOUZA'))).to eq(1.2)
      end
    end

    it 'não conta o nome antigo quando a pesquisa não confirmou decisor ou nunca rodou' do
      %w[no_result ambiguous failed not_researched].each do |status|
        expect(runner.send(:priority_multiplier, lead_with(decision_status: status, decision_name: 'Joao Palpite IA'))).to eq(1.0)
      end
    end
  end
end
