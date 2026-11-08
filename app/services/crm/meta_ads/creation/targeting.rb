# Quem vê e onde aparece (#2198, Fluxos 1 e 4): o público do grupo de anúncios.
#
# - Brasil todo, ou alguns estados. A tela manda a sigla; a região da Meta (`regions: [{ key }]`) sai da busca de
#   localização dela, guardada em cache por 30 dias.
# - Idade de 18 a 65 (65 quer dizer 65+). Categoria especial (seguro, crédito, empréstimo, investimento) trava em 18 a 65.
# - Onde aparece: Automático vai como `publisher_platforms: ["facebook", "instagram"]`, sem posição, e a Meta escolhe
#   feed, Stories ou Reels; omitir o campo incluiria Messenger, Audience Network e Threads. "Só Instagram" e "Só
#   Facebook" mandam uma plataforma.
# - O público fica como a pessoa escolheu: `advantage_audience: 0`.
class Crm::MetaAds::Creation::Targeting
  STATES = {
    'AC' => 'Acre', 'AL' => 'Alagoas', 'AP' => 'Amapá', 'AM' => 'Amazonas', 'BA' => 'Bahia', 'CE' => 'Ceará',
    'DF' => 'Distrito Federal', 'ES' => 'Espírito Santo', 'GO' => 'Goiás', 'MA' => 'Maranhão', 'MT' => 'Mato Grosso',
    'MS' => 'Mato Grosso do Sul', 'MG' => 'Minas Gerais', 'PA' => 'Pará', 'PB' => 'Paraíba', 'PR' => 'Paraná',
    'PE' => 'Pernambuco', 'PI' => 'Piauí', 'RJ' => 'Rio de Janeiro', 'RN' => 'Rio Grande do Norte',
    'RS' => 'Rio Grande do Sul', 'RO' => 'Rondônia', 'RR' => 'Roraima', 'SC' => 'Santa Catarina', 'SP' => 'São Paulo',
    'SE' => 'Sergipe', 'TO' => 'Tocantins'
  }.freeze
  PLATFORMS = { 'AUTO' => %w[facebook instagram], 'INSTAGRAM' => %w[instagram], 'FACEBOOK' => %w[facebook] }.freeze
  AGES = (18..65)
  REGION_CACHE_TTL = 30.days

  def initialize(client)
    @client = client
  end

  # draft: region ('BR' | 'STATES'), states, age_min, age_max, special_category, placement.
  def build(draft)
    ages = draft[:special_category] ? AGES.minmax : [draft[:age_min], draft[:age_max]]
    {
      geo_locations: geo(draft), age_min: ages.first, age_max: ages.last,
      publisher_platforms: PLATFORMS.fetch(draft[:placement]), targeting_automation: { advantage_audience: 0 }
    }
  end

  private

  def geo(draft)
    return { countries: ['BR'] } if draft[:region] == 'BR'

    { regions: draft[:states].map { |state| { key: region_key(state) } } }
  end

  def region_key(state)
    Rails.cache.fetch("meta_ads:region:BR:#{state}", expires_in: REGION_CACHE_TTL) { search(STATES.fetch(state)) }
  end

  # Só o nome que bate (sem acento e sem diferença de maiúscula): outro nome seria outro lugar.
  def search(name)
    result = @client.search_regions(name)
    raise Crm::MetaAds::Creation::Error.from_result(result) unless result.ok

    found = pick(brazilian_regions(result.data['data']), name)
    raise Crm::MetaAds::Creation::Error, 'invalid_audience' if found.nil?

    found['key'].to_s
  end

  def brazilian_regions(rows)
    Array(rows).select { |row| row.is_a?(Hash) && row['country_code'] == 'BR' && row['type'] == 'region' }
  end

  def pick(regions, name)
    regions.find { |row| plain(row['name']) == plain(name) }
  end

  def plain(text)
    text.to_s.unicode_normalize(:nfd).each_char.reject { |char| char.ord.between?(0x300, 0x36F) }.join.downcase
  end
end
