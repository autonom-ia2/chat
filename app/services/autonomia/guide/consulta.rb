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
  # Tetos medidos, não escolhidos no chute. Com a lista enxuta, uma caixa de
  # entrada real ocupa ~555 caracteres: 40 caixas dão ~22.000. Os tetos abaixo
  # cabem isso com folga e ainda cobrem 100 etiquetas, times ou funis.
  #
  # São TETO, não custo fixo: uma conta com três caixas gasta ~1.700
  # caracteres. Só paga o tamanho quem tem o tamanho.
  #
  # Recurso que cresce sem limite — contato, conversa — continua batendo no
  # teto, e aí o Guia diz que cortou em vez de contar a amostra como se fosse o
  # total. Esse é o comportamento certo: melhor dizer "não sei quantos" do que
  # dizer um número errado.
  MAX_ITENS = 100
  MAX_TEXTO = 40_000

  # Campo de texto acima disto é conteúdo, não identificação: numa LISTA ele só
  # ocupa espaço. Quem quiser o conteúdo pede o item.
  MAX_TEXTO_DE_CAMPO = 80

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

    return indisponivel(recurso, resposta.codigo) unless resposta.codigo.to_i == 200

    resumir(resposta.corpo)
  rescue Recusada => e
    e.message
  rescue StandardError => e
    Rails.logger.error("[autonomia][guide][consulta] account=#{@account&.id} recurso=#{recurso} #{e.class}")
    "Não consegui ler #{recurso} agora."
  end

  private

  # Isto vira texto que o modelo repassa para a pessoa, então não pode ser um
  # número de status HTTP. 404 e 403 aqui quase sempre significam a mesma coisa
  # para quem está perguntando: o recurso não está ligado nesta conta, ou o
  # perfil dela não alcança. Os outros são falha nossa, e o número fica no log.
  def indisponivel(recurso, codigo)
    Rails.logger.warn("[autonomia][guide][consulta] account=#{@account&.id} recurso=#{recurso} http=#{codigo}")
    return "Isto não está disponível nesta conta: #{recurso}." if %w[403 404].include?(codigo.to_s)

    "Não consegui ler #{recurso} agora."
  end

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
    ::Autonomia::Guide::ChamadaInterna.new(user: @user)
                                      .chamar(:get, caminho, filtros: filtros.slice(*%w[status page sort]).compact)
  end

  # Resposta de API é verbosa e cheia de campo que não ajuda a responder. Corta
  # para caber no contexto sem virar ruído — e sem inventar: o que sobra é o que
  # a API devolveu.
  def resumir(corpo)
    dados = JSON.parse(corpo.to_s)
    lista = lista_de(dados)
    return JSON.generate(lista)[0, MAX_TEXTO] unless lista.is_a?(Array)

    mostrados = cabem(lista.map { |item| enxuto(item) })
    "#{JSON.generate(mostrados)}#{quantos(mostrados.size, lista.size, total_de(dados))}"
  rescue JSON::ParserError
    corpo.to_s[0, MAX_TEXTO]
  end

  # A API embrulha a lista de jeitos diferentes conforme o recurso; leitura de um
  # item vem solta. O que não for lista segue inteiro — é o detalhe pedido.
  def lista_de(dados)
    return dados unless dados.is_a?(Hash)

    dados['payload'] || dados['data'] || dados
  end

  # Quando a plataforma informa o total, ele sobrevive ao corte da amostra.
  def total_de(dados)
    dados.is_a?(Hash) ? dados.dig('meta', 'count') : nil
  end

  # Numa LISTA o que importa é distinguir um item do outro; o detalhe de um item
  # se pede pelo item — e isso funciona, porque as rotas com `:id` estão no
  # catálogo. Sem isto, uma caixa de entrada ia inteira com seus 43 campos
  # (~3.000 bytes medidos em produção) e três caixas já estouravam o orçamento:
  # o Guia respondia "apareceu uma caixa" para quem tem três.
  #
  # O corte é por FORMA, não por nome de campo: fora nulo, vazio, aninhado e
  # texto longo. Uma lista de campos por recurso apodreceria a cada campo novo
  # da plataforma, e teria que ser escrita 270 vezes. Assim, uma caixa cai para
  # ~645 bytes mantendo nome, tipo de canal, telefone, fuso e as chaves de
  # configuração — e cabem 20 caixas onde cabia uma.
  #
  # Leitura de UM item não passa por aqui: lá o detalhe é o ponto.
  def enxuto(item)
    return item unless item.is_a?(Hash)

    item.select { |_campo, valor| identifica?(valor) }
  end

  def identifica?(valor)
    return false if valor.blank? && valor != false
    return false if valor.is_a?(Hash) || valor.is_a?(Array)

    !(valor.is_a?(String) && valor.length > MAX_TEXTO_DE_CAMPO)
  end

  # Corta por ITEM, nunca por caractere. Cortar o texto no meio de um objeto
  # entregava ao modelo uma lista que PARECIA inteira e era um pedaço: com oito
  # caixas de entrada volumosas, o JSON era truncado na quinta e o Guia
  # respondia "você tem 5 caixas" para quem tem 8, com toda a confiança.
  def cabem(lista)
    orcamento = MAX_TEXTO
    lista.first(MAX_ITENS).take_while do |item|
      orcamento -= JSON.generate(item).length + 1
      orcamento.positive?
    end
  end

  # Cortar sem dizer que cortou faz o modelo contar o pedaço. Quando a plataforma
  # informa o total, ele vai junto; quando não informa e sobrou coisa de fora, o
  # Guia diz que não sabe o total em vez de inventar um.
  def quantos(mostrados, na_pagina, total)
    return " (total nesta conta: #{total})" if total.present?
    return '' if mostrados == na_pagina && na_pagina < MAX_ITENS

    " (acima estão #{mostrados} itens; a plataforma não informou o total e a lista foi cortada, " \
      'então NÃO afirme quantos são)'
  end
end
