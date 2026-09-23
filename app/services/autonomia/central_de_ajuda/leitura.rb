# O que uma pessoa pode ler na Central de Ajuda, a partir do portal "plataforma" que o Publicador mantém.
#
# O portal é um só na instalação e mora numa conta qualquer; quem lê é gente de todas as contas. Cada
# artigo aparece só se a conta de quem lê tem o recurso do `requer` e se o `publico` vale para o papel
# dela: artigo de administrador (configuração) não aparece para quem só atende.
class Autonomia::CentralDeAjuda::Leitura
  PESOS_DA_BUSCA = { titulo: 5, descricao: 2, conteudo: 1 }.freeze
  LIMITE_DA_BUSCA = 8
  PONTUACAO = '?!.,;:()"\'“”'.freeze

  # Recursos do `requer` que não são feature flag da conta: cada um tem o seu próprio portão.
  PORTOES = {
    'autonomia_agents' => ->(conta) { ::Autonomia::Agents::Config.enabled?(conta) },
    'autonomia_prospecting' => ->(conta) { ::Autonomia::Prospecting::Config.enabled?(conta) },
    'autonomia_insurance' => ->(conta) { ::Autonomia::Insurance::Config.enabled?(conta) }
  }.freeze

  def self.ref_de(id) = id.to_s.tr('.', '-')

  def initialize(account:, account_user:)
    @account = account
    @administrador = account_user&.administrator? || false
  end

  def portal
    @portal ||= ::Portal.find_by(slug: ::Autonomia::CentralDeAjuda::Publicador::SLUG_PORTAL)
  end

  def artigos
    @artigos ||= begin
      todos = portal ? portal.articles.published.includes(:category).where('articles.slug LIKE ?', 'plataforma-%').to_a : []
      todos.select { |artigo| visivel?(artigo) }.sort_by { |artigo| [artigo.category&.position.to_i, artigo.position.to_i] }
    end
  end

  def capitulos
    artigos.group_by(&:category).map do |categoria, lista|
      { id: capitulo_id(categoria), titulo: categoria&.name, artigos: lista.map { |artigo| resumo(artigo) } }
    end
  end

  def artigo(ref)
    artigos.find { |artigo| central(artigo)['id'] == ref.to_s.tr('-', '.') }
  end

  def vizinhos(artigo)
    lista = artigos.select { |outro| outro.category_id == artigo.category_id }
    indice = lista.index(artigo)
    anterior = indice.positive? ? lista[indice - 1] : nil
    [anterior, lista[indice + 1]].map { |vizinho| vizinho && resumo(vizinho) }
  end

  # Busca por palavras: todas precisam aparecer no artigo; título pesa mais que descrição, que pesa
  # mais que o texto. Sem acento e sem maiúscula, dos dois lados.
  def buscar(termo)
    palavras = normalizar(termo).split.uniq
    return [] if palavras.empty?

    pontuados(palavras).sort_by { |pontos, artigo| [-pontos, artigos.index(artigo)] }
                       .first(LIMITE_DA_BUSCA).map { |_, artigo| resumo(artigo) }
  end

  def resumo(artigo)
    { id: central(artigo)['id'], ref: self.class.ref_de(central(artigo)['id']), titulo: artigo.title,
      descricao: artigo.description, capitulo: artigo.category&.name }
  end

  def central(artigo) = artigo.meta.to_h['central'] || {}

  private

  def visivel?(artigo)
    meta = central(artigo)
    return false if meta['publico'] == 'admin' && !@administrador

    recurso_liberado?(meta['requer'])
  end

  def recurso_liberado?(requer)
    return true if requer.blank?

    portao = PORTOES[requer]
    portao ? portao.call(@account) : @account.feature_enabled?(requer)
  end

  def capitulo_id(categoria) = categoria&.slug.to_s.delete_prefix('capitulo-')

  # [pontos, artigo] de cada artigo que tem todas as palavras em algum campo.
  def pontuados(palavras)
    artigos.filter_map do |artigo|
      campos = campos_normalizados(artigo)
      next unless palavras.all? { |palavra| campos.values.any? { |texto| texto.include?(palavra) } }

      [pontuacao(campos, palavras), artigo]
    end
  end

  def campos_normalizados(artigo)
    { titulo: normalizar(artigo.title), descricao: normalizar(artigo.description), conteudo: normalizar(artigo.content) }
  end

  def pontuacao(campos, palavras)
    palavras.sum { |palavra| PESOS_DA_BUSCA.sum { |campo, peso| campos[campo].include?(palavra) ? peso : 0 } }
  end

  def normalizar(texto)
    I18n.transliterate(texto.to_s.downcase).delete(PONTUACAO)
  end
end
