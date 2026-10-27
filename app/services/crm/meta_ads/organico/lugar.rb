# Seus posts (#2199): o que a Página (Crm::MetaAds::Organico::Pagina) e o Instagram (Crm::MetaAds::Organico::Instagram)
# têm em comum. Cada chamada à Meta passa por `ler`: permissão ou token recusados viram o cartão "Libere…"
# (needs_permission); qualquer outra falha sobe como Indisponivel.
class Crm::MetaAds::Organico::Lugar
  TOP_POSTS = 3

  # Permissão (código 10 e 200–299) ou token (190) recusados.
  class Recusa < StandardError; end

  def initialize(channel:, periodo:)
    @channel = channel
    @periodo = periodo
  end

  def perform
    numeros
  rescue Recusa
    bloqueado
  end

  private

  attr_reader :channel, :periodo

  def ler(result)
    return result.data if result.ok
    raise Recusa if result.token_invalid? || result.scope_error?

    raise Crm::MetaAds::Organico::Indisponivel, result.error_message
  end

  # Número de um post só (alcance do post): objeto apagado ou sem leitura (100, 803) ou recusa só daquele post
  # (10, 200–299) não condenam o lugar inteiro; o post fica sem o número. Token inválido e Meta fora seguem `ler`.
  def ler_do_post(result)
    return if !result.ok && (result.object_error? || result.scope_error?)

    ler(result)
  end

  def melhores(posts)
    posts.max_by(TOP_POSTS) { |post| post[:interactions] }
  end

  # Métrica com um total no período (metric_type=total_value, Instagram).
  def total(data, name, dimensao: nil)
    valor = metrica(data, name)&.dig('total_value')
    return valor&.dig('value') unless dimensao

    resultados = Array(valor&.dig('breakdowns')).flat_map { |recorte| Array(recorte['results']) }
    resultados.find { |resultado| resultado['dimension_values'] == [dimensao] }&.dig('value')
  end

  # Métrica com um valor por dia (Página): soma do período. `where` filtra o lado do recorte.
  def soma(data, name, **where)
    valores(data, name).sum { |valor| where.all? { |chave, esperado| valor[chave.to_s] == esperado } ? valor['value'].to_i : 0 }
  end

  def primeiro(data, name)
    valores(data, name).first&.dig('value').to_i
  end

  def valores(data, name)
    Array(metrica(data, name)&.dig('values'))
  end

  def metrica(data, name)
    Array(data.to_h['data']).find { |entry| entry['name'] == name }
  end

  def client(**)
    Meta::AdsGraphClient.new(access_token: token, api_version: Crm::MetaAds::Organico::API_VERSION, **)
  end
end
