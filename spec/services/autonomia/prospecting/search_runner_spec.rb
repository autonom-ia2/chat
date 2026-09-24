require 'rails_helper'

RSpec.describe Autonomia::Prospecting::SearchRunner do
  let(:account) { create(:account) }
  let(:user) { create(:user, :administrator, account: account) }

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

    described_class.new(account: account, user: user, params: params).perform
    described_class.new(account: other_account, user: other_user, params: params).perform

    expect(account.autonomia_prospecting_leads.count).to eq(1)
    expect(other_account.autonomia_prospecting_leads.count).to eq(1)
  end

  it 'rejects limits over account settings' do
    Autonomia::Prospecting::Setting.for_account(account).update!(max_results_per_search: 2)

    expect do
      described_class.new(
        account: account,
        user: user,
        params: { query: 'hotel', location: 'Sao Paulo, SP', requested_limit: 3 }
      ).perform
    end.to raise_error(ActiveRecord::RecordInvalid, /less than or equal to 2/)
  end

  it 'rejects google places when account key is missing' do
    Autonomia::Prospecting::Setting.for_account(account).update!(
      provider: 'google_places',
      provider_enabled: true
    )

    expect do
      described_class.new(
        account: account,
        user: user,
        params: { query: 'hotel', location: 'Sao Paulo, SP', requested_limit: 1, provider: 'google_places' }
      ).perform
    end.to raise_error(Autonomia::Prospecting::SearchRunner::ProviderError, /API key/)
  end

  it 'rejects google places when daily usage limit is exhausted' do
    Autonomia::Prospecting::Setting.for_account(account).update!(
      provider: 'google_places',
      provider_enabled: true,
      google_places_api_key: 'secret-key',
      daily_limit: 1
    )
    Autonomia::Prospecting::Search.create!(
      account: account,
      user: user,
      query: 'padaria',
      requested_limit: 1,
      consumed_api_units: 1
    )

    expect do
      described_class.new(
        account: account,
        user: user,
        params: { query: 'hotel', location: 'Sao Paulo, SP', requested_limit: 1 }
      ).perform
    end.to raise_error(Autonomia::Prospecting::SearchRunner::ProviderError, /Daily limit/)
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

  # Caracterização do motor antes da E0 (#683). Cada teste afirma o que o código
  # faz HOJE. Onde o comportamento está errado, o comentário DIVERGE diz o que
  # deveria ser, para a frente que corrigir trocar a expectativa de propósito.
  describe 'caracterização antes da E0 (#683)' do
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

    def stub_google_places(places_payload, api_key: 'chave-da-conta')
      stub_request(:post, google_endpoint)
        .with(headers: { 'X-Goog-Api-Key' => api_key })
        .to_return(status: 200, body: { places: places_payload }.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    describe 'provider padrão' do
      it 'cria a configuração da conta com provider mock e google desligado' do
        # DIVERGE: google_places deve ser o provider padrão (migration muda o default da coluna).
        expect(setting.provider).to eq('mock')
        expect(setting.provider_enabled).to be(false)
      end

      it 'recusa google_places com o provider desligado na conta' do
        # DIVERGE: com chave de plataforma, provider_enabled da conta não deve governar a busca.
        setting.update!(provider: 'google_places', provider_enabled: false, google_places_api_key: 'chave-da-conta')

        expect { run_search(query: 'hotel', location: 'Curitiba, PR', requested_limit: 1) }
          .to raise_error(described_class::ProviderError, /disabled for this account/)
      end

      it 'chama o Google Places com a chave gravada na conta' do
        # DIVERGE: deve usar GOOGLE_PLACES_API_KEY da plataforma (InstallationConfig), não a chave da conta.
        setting.update!(provider: 'google_places', provider_enabled: true, google_places_api_key: 'chave-da-conta')
        stub_google_places([google_place])

        result = run_search(query: 'clinica', location: 'Curitiba, PR', requested_limit: 1)

        expect(result.search).to be_completed
        expect(result.search.consumed_api_units).to eq(1)
        expect(result.leads.map(&:provider_place_id)).to eq(['places/google-1'])
        expect(a_request(:post, google_endpoint).with(headers: { 'X-Goog-Api-Key' => 'chave-da-conta' })).to have_been_made.once
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

      it 'has_photos yes zera o resultado mesmo com fotos no payload do provider mock' do
        # DIVERGE: has_photos deve olhar as fotos do lugar (raw_payload.photos); o provider nunca grava :has_photos.
        params = { query: 'dentista', location: 'Curitiba, PR', radius: 1000, area_type: 'radius', area_config: {}, limit: 8 }
        raw_places = mock_provider_class.new(**params).search
        expect(raw_places.count { |place| place.dig(:raw_payload, :photos).present? }).to be_positive

        result = run_search(query: 'dentista', location: 'Curitiba, PR', requested_limit: 8, advanced_filters: { has_photos: 'yes' })

        expect(result.leads).to be_empty
      end

      it 'has_photos no deixa passar todos, inclusive quem tem foto' do
        # DIVERGE: has_photos no deve manter só quem não tem foto.
        result = run_search(query: 'dentista', location: 'Curitiba, PR', requested_limit: 8, advanced_filters: { has_photos: 'no' })

        expect(result.leads.size).to eq(8)
      end

      it 'open_now yes e no zeram o resultado porque o provider nunca grava :open_now' do
        # DIVERGE: open_now deve ler currentOpeningHours.openNow do lugar; yes mantém abertos, no mantém fechados.
        yes_result = run_search(query: 'dentista', location: 'Curitiba, PR', requested_limit: 8, advanced_filters: { open_now: 'yes' })
        no_result = run_search(query: 'dentista', location: 'Curitiba, PR', requested_limit: 8, advanced_filters: { open_now: 'no' })

        expect(yes_result.leads).to be_empty
        expect(no_result.leads).to be_empty
      end

      it 'no Google Places, has_photos yes e open_now yes descartam um lugar aberto e com foto' do
        # DIVERGE: o lugar tem photos e currentOpeningHours.openNow=true; os dois filtros deveriam mantê-lo.
        setting.update!(provider: 'google_places', provider_enabled: true, google_places_api_key: 'chave-da-conta')
        stub_google_places([google_place])

        with_photos = run_search(query: 'clinica', location: 'Curitiba, PR', requested_limit: 1, advanced_filters: { has_photos: 'yes' })
        open_now = run_search(query: 'clinica', location: 'Curitiba, PR', requested_limit: 1, advanced_filters: { open_now: 'yes' })

        expect(with_photos.leads).to be_empty
        expect(open_now.leads).to be_empty
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
          .to raise_error(ActiveRecord::RecordInvalid, /greater than 0/)
      end

      it 'recusa 21 e 60 com o max_results_per_search padrão de 20' do
        # DIVERGE: o teto passa a ser 60 (teto de produto) e max_results_per_search deixa de ser aplicado.
        expect { run_search(query: 'padaria', location: 'Curitiba, PR', requested_limit: 21) }
          .to raise_error(ActiveRecord::RecordInvalid, /less than or equal to 20/)
        expect { run_search(query: 'padaria', location: 'Curitiba, PR', requested_limit: 60) }
          .to raise_error(ActiveRecord::RecordInvalid, /less than or equal to 20/)
      end

      it 'pede no máximo 20 resultados ao Google Places mesmo com limite maior configurado' do
        setting.update!(provider: 'google_places', provider_enabled: true, google_places_api_key: 'chave-da-conta',
                        max_results_per_search: 60)
        stub_google_places([google_place])

        run_search(query: 'clinica', location: 'Curitiba, PR', requested_limit: 60)

        expect(a_request(:post, google_endpoint).with { |req| JSON.parse(req.body)['maxResultCount'] == 20 }).to have_been_made.once
      end
    end

    describe 'limites de consumo' do
      before do
        setting.update!(provider: 'google_places', provider_enabled: true, google_places_api_key: 'chave-da-conta')
      end

      it 'recusa quando o monthly_limit do mês já foi consumido' do
        # DIVERGE: a E0 remove daily_limit e monthly_limit; a busca deve seguir.
        setting.update!(monthly_limit: 2)
        Autonomia::Prospecting::Search.create!(account: account, user: user, query: 'padaria', requested_limit: 1, consumed_api_units: 2)

        expect { run_search(query: 'hotel', location: 'Curitiba, PR', requested_limit: 1) }
          .to raise_error(described_class::ProviderError, /Monthly limit/)
      end

      it 'conta 3 unidades quando a expansão automática de raio está ligada' do
        # DIVERGE: a E0 remove a trava; a estimativa por raio deixa de bloquear.
        setting.update!(daily_limit: 2)

        expect do
          run_search(query: 'hotel', location: 'Curitiba, PR', requested_limit: 1, filters: { auto_expand_radius: true })
        end.to raise_error(described_class::ProviderError, /Daily limit/)
      end

      it 'não trava o provider mock, que não consome unidade' do
        setting.update!(provider: 'mock', daily_limit: 1, monthly_limit: 1)
        Autonomia::Prospecting::Search.create!(account: account, user: user, query: 'padaria', requested_limit: 1, consumed_api_units: 5)

        expect(run_search(query: 'hotel', location: 'Curitiba, PR', requested_limit: 1).search).to be_completed
      end

      it 'serve do cache antes de conferir o limite diário' do
        setting.update!(daily_limit: 1, cache_ttl_seconds: 3600)
        stub_google_places([google_place])
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

      it 'serve uma busca que falhou como cache vazio' do
        # DIVERGE: só busca completed pode entrar no cache; a segunda busca deveria rodar o provider de novo.
        failing_provider = instance_double(mock_provider_class)
        allow(failing_provider).to receive(:search).and_raise(StandardError, 'provider fora do ar')
        allow(mock_provider_class).to receive(:new).and_return(failing_provider)

        expect { run_search(params) }.to raise_error(StandardError, 'provider fora do ar')
        failed_search = account.autonomia_prospecting_searches.order(:id).last
        expect(failed_search).to be_failed
        expect(failed_search.metadata['error']).to eq('provider fora do ar')

        allow(mock_provider_class).to receive(:new).and_call_original
        second = run_search(params)

        expect(second.search).to be_cached
        expect(second.search.metadata['cached_from_search_id']).to eq(failed_search.id)
        expect(second.leads).to be_empty
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

      it 'deduplica pelo telefone quando o lugar não tem provider_place_id' do
        stub_mock_provider([places.first.merge(provider_place_id: nil)])

        result = run_search(query: 'dentista', location: 'Curitiba, PR', requested_limit: 1)

        expect(result.leads.first.dedupe_key).to eq('mock:+5541999990001')
      end

      it 'derruba a busca quando outra grava o mesmo lugar entre a leitura e o insert' do
        # DIVERGE: duas buscas simultâneas sobre o mesmo lugar não podem derrubar uma à outra;
        # quem perde a corrida deve reaproveitar o lead gravado pela outra.
        stub_mock_provider([places.first])
        competitor_saved = false
        allow(Autonomia::Prospecting::Lead).to receive(:new).and_wrap_original do |original, *args, &block|
          unless competitor_saved
            competitor_saved = true
            original.call(account: account, provider: 'mock', provider_place_id: 'places/a', name: 'Gravado pela outra busca').save!
          end
          original.call(*args, &block)
        end

        expect { run_search(query: 'dentista', location: 'Curitiba, PR', requested_limit: 1) }
          .to raise_error(ActiveRecord::RecordInvalid, /Dedupe key has already been taken/)
        expect(account.autonomia_prospecting_searches.order(:id).last).to be_failed
      end
    end
  end
end
