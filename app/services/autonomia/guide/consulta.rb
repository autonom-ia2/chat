# O Guia consultando a plataforma inteira, como quem perguntou (issue #533, 2ª volta).
#
# A primeira versão tinha cinco assuntos escritos à mão, e cobertura de cinco
# assuntos nunca vira cobertura da plataforma. Aqui o catálogo é DERIVADO das
# rotas de leitura da API da conta — as mesmas 268 que a interface usa — do mesmo
# jeito que o mapa do Guia passou a sair do roteador.
#
# O que sustenta isso com segurança não é uma lista minha, é o critério do
# Rodrigo: **o que a pessoa vê na tela, a IA vê; o que ela não vê, a IA não vê.**
# Por isso a consulta roda como o usuário, pelo mesmo caminho da interface, e
# herda Pundit, papel, funções personalizadas e isolamento de conta. Chave de
# integração continua fora porque a própria API a devolve mascarada.
#
# Só leitura: escrever é outra fatia, com confirmação (#536).
class Autonomia::Guide::Consulta
  class Recusada < StandardError; end

  PREFIXO = '/api/v1/accounts/'.freeze
  MAX_ITENS = 25
  MAX_TEXTO = 6_000

  # Rotas que pedem identificador que o Guia não tem como adivinhar ficam fora do
  # catálogo oferecido ao modelo: sem o id, a chamada só produziria erro. O
  # parâmetro no roteador começa com dois pontos — basta procurar o caractere.
  PARAMETRO = ':'.freeze

  def initialize(account:, user:, account_user: nil)
    @account = account
    @user = user
    @account_user = account_user || account&.account_users&.find_by(user_id: user&.id)
  end

  # O que o modelo pode pedir, em linguagem de rota: 'inboxes', 'labels',
  # 'crm/pipelines'. Deriva do roteador, então nasce completo e cresce sozinho.
  def catalogo
    @catalogo ||= Rails.application.routes.routes.filter_map do |rota|
      next unless rota.verb.to_s == 'GET'

      caminho = rota.path.spec.to_s.sub('(.:format)', '')
      next unless caminho.start_with?(PREFIXO)

      recurso = caminho.sub("#{PREFIXO}:account_id/", '')
      next if recurso.blank?

      recurso
    end.uniq.sort
  end

  # Executa a leitura como o usuário e devolve o corpo já enxuto, pronto para
  # virar contexto. Nunca levanta para o chamador: erro vira recusa explicada.
  #
  # `parametros` preenche o `:id` de rotas como 'contacts/:id'. Antes essas rotas
  # ficavam fora do catálogo, e isso tirava 145 das 270 leituras da plataforma: o
  # Guia listava suas caixas e não conseguia abrir nenhuma.
  def ler(recurso, parametros = {}, filtros = {})
    caminho = montar_caminho(recurso, parametros)
    resposta = requisitar(caminho, filtros)

    return "Não consegui ler #{recurso}: a plataforma respondeu #{resposta.code}." unless resposta.code.to_i == 200

    resumir(resposta.body)
  rescue Recusada => e
    e.message
  rescue StandardError => e
    Rails.logger.error("[autonomia][guide][consulta] account=#{@account&.id} recurso=#{recurso} #{e.class}")
    "Não consegui ler #{recurso} agora."
  end

  private

  # O caminho é sempre montado com o id DESTA conta, e cada `:id` vira um
  # segmento escapado — valor vindo do modelo nunca entra como pedaço de rota.
  def montar_caminho(recurso, parametros)
    limpo = recurso.to_s.strip.delete_prefix('/')
    raise Recusada, 'Não sei consultar isso.' unless catalogo.include?(limpo)

    valores = (parametros || {}).transform_keys(&:to_s)
    segmentos = limpo.split('/').map do |segmento|
      next segmento unless segmento.start_with?(PARAMETRO)

      chave = segmento.delete_prefix(PARAMETRO)
      valor = valores[chave].to_s.strip
      raise Recusada, "Para isso eu preciso saber qual #{chave}." if valor.blank?

      CGI.escape(valor)
    end

    "#{PREFIXO}#{@account.id}/#{segmentos.join('/')}"
  end

  # A chamada sai com o token do próprio usuário: é o mecanismo oficial da API e
  # é o que garante que a resposta seja exatamente a que ele receberia na tela.
  # O token nunca é registrado em log.
  def requisitar(caminho, filtros)
    uri = URI.parse("http://127.0.0.1:#{porta}#{caminho}")
    uri.query = URI.encode_www_form(filtros.slice(*%w[status page sort]).compact) if filtros.present?

    requisicao = Net::HTTP::Get.new(uri)
    requisicao['api_access_token'] = @user.access_token.token
    requisicao['Content-Type'] = 'application/json'

    Net::HTTP.start(uri.hostname, uri.port, open_timeout: 2, read_timeout: 8) do |http|
      http.request(requisicao)
    end
  end

  # A porta é a do próprio processo, não um palpite: o Procfile sobe o Rails com
  # `-p $PORT`. Se ela mudar e isto ficasse fixo, toda leitura falharia calada —
  # que é exatamente o modo de falha que esta issue veio consertar.
  def porta
    ENV.fetch('PORT', 3000)
  end

  # Resposta de API é verbosa e cheia de campo que não ajuda a responder. Corta
  # para caber no contexto sem virar ruído — e sem inventar: o que sobra é o que
  # a API devolveu.
  def resumir(corpo)
    dados = JSON.parse(corpo.to_s)
    total = dados.is_a?(Hash) ? dados.dig('meta', 'count') : nil
    lista = dados.is_a?(Hash) ? (dados['payload'] || dados['data'] || dados) : dados
    return JSON.generate(lista)[0, MAX_TEXTO] unless lista.is_a?(Array)

    "#{JSON.generate(lista.first(MAX_ITENS))[0, MAX_TEXTO]}#{quantos(lista, total)}"
  rescue JSON::ParserError
    corpo.to_s[0, MAX_TEXTO]
  end

  # Cortar a lista sem dizer que cortou faz o modelo contar o pedaço e responder
  # "você tem 25" para quem tem 300 — errado, com cara de certeza. Quando a
  # plataforma informa o total, ele vai junto; quando não informa e a lista
  # encheu, o Guia diz que não sabe o total em vez de inventar um.
  def quantos(lista, total)
    return " (total nesta conta: #{total})" if total.present?
    return '' if lista.size < MAX_ITENS

    " (acima estão os #{MAX_ITENS} primeiros; a plataforma não informou o total, então NÃO afirme quantos são)"
  end
end
