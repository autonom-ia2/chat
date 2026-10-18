# Localização pelo "+" da conversa (#1702): o atendente procura o endereço ou o nome do lugar e escolhe; o ponto no
# mapa vem do Google. Reaproveita o Google Places da Prospecção (mesma chave da plataforma, mesmas mensagens de erro em
# português), sem o filtro de cidade de lá: aqui vale endereço, estabelecimento e ponto de referência.
#
# Custo (revisão do #1702): as sugestões e o detalhe vão na mesma sessão do Google (`sessionToken`), que cobra a busca
# como uma só; o detalhe fica em cache por lugar; e o id do lugar só passa se for um id do Google (letras, números, - e _),
# para ninguém montar outra chamada à API com a chave da plataforma.
class ConversaCanal::BuscaDeLugar < Autonomia::Prospecting::Providers::GooglePlacesLocation
  DETAILS_FIELD_MASK = 'id,displayName,formattedAddress,location'.freeze
  MINIMO_DE_LETRAS = 3
  CACHE_DO_LUGAR = 1.day
  LETRAS_DO_ID = [*'a'..'z', *'A'..'Z', *'0'..'9', '-', '_'].freeze
  TAMANHO_DA_SESSAO = 64

  def self.para(account, sessao: nil)
    new(api_key: chave, country: nil, account_id: account.id).tap { |busca| busca.sessao = sessao }
  end

  def self.chave
    Autonomia::Prospecting::Setting.platform_config('GOOGLE_PLACES_API_KEY')
  end

  def self.configurada?
    chave.present?
  end

  def self.id_do_google?(place_id)
    texto = place_id.to_s
    texto.present? && texto.length <= 300 && texto.each_char.all? { |letra| LETRAS_DO_ID.include?(letra) }
  end

  attr_reader :sessao

  def sessao=(valor)
    texto = valor.to_s
    @sessao = texto if texto.present? && texto.length <= TAMANHO_DA_SESSAO && texto.each_char.all? { |l| LETRAS_DO_ID.include?(l) }
  end

  def suggestions(query)
    return [] if query.to_s.strip.length < MINIMO_DE_LETRAS

    super
  end

  # { place_id, nome, endereco, latitude, longitude }
  def details(place_id)
    Rails.cache.fetch(['conversa_canal/lugar', place_id], expires_in: CACHE_DO_LUGAR) { detalhe_no_google(place_id) }
  end

  private

  def detalhe_no_google(place_id)
    body = request('details') do
      HTTParty.get("#{PLACE_DETAILS_ENDPOINT}/#{place_id}", query: locale_params.merge(sessao_params),
                                                            headers: headers(DETAILS_FIELD_MASK), timeout: TIMEOUT_SECONDS)
    end

    {
      place_id: body['id'],
      nome: body.dig('displayName', 'text'),
      endereco: body['formattedAddress'],
      latitude: body.dig('location', 'latitude'),
      longitude: body.dig('location', 'longitude')
    }
  end

  def autocomplete_body(query)
    { input: query, includedRegionCodes: [@country.downcase] }.merge(locale_params).merge(sessao_params)
  end

  def sessao_params
    @sessao ? { sessionToken: @sessao } : {}
  end
end
