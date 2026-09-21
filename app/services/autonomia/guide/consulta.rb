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

  # Campo de texto acima disto é conteúdo longo, não identificação. O limite é
  # folgado de propósito: com 80 caracteres, a resposta pronta perdia o próprio
  # texto e a avaliação perdia o comentário do cliente — e esses dois recursos
  # não têm rota de item, então o conteúdo ficava inalcançável. Quem controla o
  # volume é o orçamento total, que corta por item inteiro.
  MAX_TEXTO_DE_CAMPO = 400

  # Segredo NUNCA sai daqui, em lista ou em item.
  #
  # O corte deste arquivo é por forma, e segredo é justamente o caso em que a
  # forma não denuncia nada: `hmac_token`, `imap_password`, `smtp_password` e o
  # `secret` de webhook são strings curtas, iguaizinhas a um nome de caixa. Iam
  # inteiros para o modelo. Aqui o nome é a única coisa que importa, então a
  # lista é por nome mesmo — e vale para qualquer recurso dos 270.
  SEGREDOS = %w[
    secret hmac_token inbox_identifier
    password imap_password smtp_password
    token access_token auth_token refresh_token api_key apikey
    private_key client_secret signing_key webhook_secret
  ].freeze

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

    case codigo.to_s
    # Recurso desligado na conta.
    when '404' then "Isto não está disponível nesta conta: #{recurso}."
    # Ligado, mas fora do alcance do perfil de quem perguntou. Dizer que "não
    # está disponível" faria a pessoa achar que precisa contratar o que já tem.
    when '403' then "O perfil de quem perguntou não tem acesso a isto: #{recurso}."
    else "Não consegui ler #{recurso} agora."
    end
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
    return item_unico(lista) unless lista.is_a?(Array)

    mostrados = cabem(lista.map { |item| enxuto(item) })
    "#{JSON.generate(mostrados)}#{quantos(mostrados.size, lista.size, total_de(dados))}"
  rescue JSON::ParserError
    corpo.to_s[0, MAX_TEXTO]
  end

  # O que não é lista é o detalhe de um item: vai inteiro, menos os segredos.
  # Se ainda assim estourar, o corte é por caractere e por isso PRECISA avisar —
  # calado, ele entrega ao modelo um JSON partido no meio que parece completo.
  def item_unico(dados)
    texto = JSON.generate(sem_segredos(dados))
    return texto if texto.length <= MAX_TEXTO

    "#{texto[0, MAX_TEXTO]} (esta resposta foi cortada no meio; NÃO afirme totais nem trate a lista " \
      'acima como completa)'
  end

  # A API embrulha a lista de jeitos diferentes conforme o recurso, e às vezes em
  # mais de um nível: conversas vêm como `data: { meta:, payload: [...] }`.
  # Desembrulhar um nível só fazia conversas e notificações caírem no caminho do
  # item único — sem enxugar, sem corte por item e sem aviso. A partir de umas
  # doze conversas o modelo recebia um JSON partido achando que estava inteiro.
  def lista_de(dados)
    return dados unless dados.is_a?(Hash)

    interno = dados['payload'] || dados['data']
    return dados if interno.nil?
    return interno.values.first if uma_lista_embrulhada?(interno)

    lista_de(interno)
  end

  def uma_lista_embrulhada?(interno)
    interno.is_a?(Hash) && interno.size == 1 && interno.values.first.is_a?(Array)
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

    sem_segredos(item).select { |_campo, valor| identifica?(valor) }
  end

  # Vale em lista e em item único: o nome do campo é o que denuncia o segredo.
  def sem_segredos(dados)
    return dados unless dados.is_a?(Hash)

    dados.reject { |campo, _valor| segredo?(campo) }
  end

  def segredo?(campo)
    nome = campo.to_s.downcase
    SEGREDOS.any? { |proibido| nome == proibido || nome.end_with?("_#{proibido}") }
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
  # Quando a plataforma informa o total, ele vai junto e o modelo pode contar.
  # Quando NÃO informa, o silêncio é proibido: a lista pode ser uma página — a
  # API pagina de 15, de 25, depende do recurso — e ninguém aqui tem como saber
  # o tamanho da página. Usar o nosso teto de itens como sinal de "veio inteira"
  # era um proxy errado: subi o teto de 25 para 100 e o aviso sumiu sozinho,
  # fazendo o Guia entregar 25 de 30 avaliações como se fossem todas.
  def quantos(mostrados, na_pagina, total)
    return " (total nesta conta: #{total})" if total.present?

    if mostrados < na_pagina
      return " (a plataforma entregou #{na_pagina} e mostrei #{mostrados}; o resto ficou de fora, " \
             'então NÃO afirme quantos são)'
    end

    " (a plataforma entregou #{mostrados} e estão todos acima; ela não informou o total e pode " \
      'paginar, então diga quantos recebeu, não que este é o total da conta)'
  end
end
