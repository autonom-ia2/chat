# Seus posts (#2199): o que a Página (Crm::MetaAds::Organico::Pagina) e o Instagram (Crm::MetaAds::Organico::Instagram)
# têm em comum. Cada chamada à Meta passa por `ler`: permissão ou token recusados viram o cartão "Libere…"
# (needs_permission); qualquer outra falha sobe como Indisponivel.
class Crm::MetaAds::Organico::Lugar
  TOP_POSTS = 3
  # Os números que a tela compara com o período anterior.
  COMPARADOS = %i[reach views interactions new_followers].freeze
  # Vezes que os posts apareceram sem anúncio no período anterior até as quais ele é tido como parado: a tela diz
  # "primeiro período com dado" em vez de "X a mais".
  VIEWS_SEM_ATIVIDADE = 0

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

    raise Crm::MetaAds::Organico::Indisponivel.new(result.error_message, codigo: result.error_code || result.http_code)
  end

  # Número de um post só (alcance do post): objeto apagado ou sem leitura (100, 803) ou recusa só daquele post
  # (10, 200–299) não condenam o lugar inteiro; o post fica sem o número. Token inválido e Meta fora seguem `ler`.
  def ler_do_post(result)
    return if !result.ok && (result.object_error? || result.scope_error?)

    ler(result)
  end

  # O período anterior só serve de comparação se os posts apareceram nele sem anúncio. Parado, "X a mais" compararia
  # com nada; a tela diz então que este é o primeiro período com dado (first_period).
  def comparacao
    return { previous: nil } unless compara?

    anterior = janela(periodo.anterior).slice(*COMPARADOS)
    # Sem as vezes do anterior (a Meta não mandou), não se sabe se ele estava parado: sem comparação.
    return { previous: nil } if anterior[:views].nil?
    return { previous: nil, first_period: true } if anterior[:views] <= VIEWS_SEM_ATIVIDADE

    { previous: anterior }
  end

  def indisponivel!(motivo)
    raise Crm::MetaAds::Organico::Indisponivel.new(motivo, codigo: 'recorte')
  end

  def compara?
    true
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

  # Métrica com um valor por dia (Página): soma do período. `where` filtra o lado do recorte. Métrica, lado ou valor que
  # não veio é "sem número" (nil), nunca 0: a Meta manda os dois lados de is_from_ads todo dia, até com 0 (chamada real
  # de 27/10), então lado ausente é falta de dado. Dia sem valor fica fora da soma.
  def soma(data, name, **where)
    numeros = valores(data, name).filter_map do |valor|
      valor['value'] if valor['value'].is_a?(Numeric) && where.all? { |chave, esperado| valor[chave.to_s] == esperado }
    end
    numeros.sum if numeros.any?
  end

  # O primeiro valor da métrica; valor que não é número ("", "N/A") é "sem número" (nil), nunca 0.
  def primeiro(data, name)
    valor = valores(data, name).first&.dig('value')
    valor.is_a?(Numeric) ? valor.to_i : nil
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
