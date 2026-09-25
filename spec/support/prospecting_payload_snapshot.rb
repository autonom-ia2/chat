# Retrato do que a tela da prospecção recebe numa conta ainda no motor de nota legado (#681). O arquivo de referência foi
# gravado com o código de antes do modo sombra; o spec de caracterização compara byte a byte com ele. Ids e datas mudam
# de execução para execução e entram como marcador, o resto entra como veio.
module ProspectingPayloadSnapshot
  FIXTURE = 'prospecting/legacy_engine_payloads.json'.freeze
  FROZEN_AT = Time.zone.parse('2026-09-25 12:00:00 UTC')
  VOLATILE_KEYS = %w[id created_at updated_at contact_id crm_card_id scoring_profile_id cached_from_search_id crm_pipeline_id
                     crm_stage_id company_profile_id].freeze

  module_function

  # Lugares do fixture do Google com avaliações datadas, para a atividade entrar na nota.
  def places(fixture)
    fixture['places'].each_with_index.map do |place, index|
      next place unless index.even?

      place.merge('reviews' => [{ 'rating' => 5, 'publishTime' => (FROZEN_AT - (index * 40).days).iso8601,
                                  'text' => { 'text' => "Avaliação #{index}" } }])
    end
  end

  def normalize(value)
    case value
    when Hash
      value.to_h { |key, item| [key, volatile?(key) ? "<#{key}>" : normalize(item)] }
    when Array
      value.map { |item| normalize(item) }
    else
      value
    end
  end

  def volatile?(key)
    VOLATILE_KEYS.include?(key.to_s)
  end
end

# Os pedidos que a tela faz numa conta de motor legado: busca GMN, busca geral, reabrir a primeira e abrir um lead.
RSpec.shared_context 'with prospecting legacy engine snapshot' do
  let(:snapshot_account) { create(:account) }
  let(:snapshot_admin) { create(:user, :administrator, account: snapshot_account) }
  let(:snapshot_base) { "/api/v1/accounts/#{snapshot_account.id}/autonomia/prospecting" }
  let(:snapshot_google_fixture) { JSON.parse(file_fixture('google_places/search_text_filtros.json').read) }

  def snapshot_search(query, score_mode)
    post "#{snapshot_base}/searches",
         params: { search: { query: query, location: 'Curitiba, PR', requested_limit: 8, metadata: { score_mode: score_mode } } },
         headers: auth_headers(snapshot_admin), as: :json
    raise "busca recusada: #{response.status}" unless response.status == 201

    response.parsed_body['payload']
  end

  def snapshot_get(path)
    get "#{snapshot_base}/#{path}", headers: auth_headers(snapshot_admin)
    raise "leitura recusada: #{response.status}" unless response.status == 200

    response.parsed_body['payload']
  end

  def legacy_engine_snapshot
    Autonomia::Prospecting::Config.enable_for!(snapshot_account)
    Autonomia::Prospecting::Setting.for_account(snapshot_account).update!(provider: 'google_places', cache_ttl_seconds: 0)
    places = ProspectingPayloadSnapshot.places(snapshot_google_fixture)
    stub_request(:post, Autonomia::Prospecting::Providers::GooglePlacesProvider::ENDPOINT)
      .to_return(status: 200, body: snapshot_google_fixture.merge('places' => places).to_json, headers: { 'Content-Type' => 'application/json' })

    travel_to(ProspectingPayloadSnapshot::FROZEN_AT) do
      gbp = snapshot_search('padaria', 'gbp')
      general = snapshot_search('padaria no batel', 'general')
      reopened = snapshot_get("searches/#{gbp.dig('search', 'id')}")
      lead = snapshot_get("leads/#{gbp['leads'].first['id']}")
      ProspectingPayloadSnapshot.normalize('gbp' => gbp, 'general' => general, 'reopened' => reopened, 'lead' => lead)
    end
  end
end
