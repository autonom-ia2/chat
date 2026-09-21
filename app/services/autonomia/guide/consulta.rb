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
    #
    # 401 está aqui porque é o que esta aplicação devolve quando o Pundit nega:
    # `render_unauthorized` responde `:unauthorized`. Eu tinha tratado só o 403,
    # que nunca chega — e negativa de permissão caía no genérico, fazendo quem
    # não tem acesso ouvir "deu erro, tente de novo".
    when '401', '403' then "O perfil de quem perguntou não tem acesso a isto: #{recurso}."
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
  #
  # Procura no mesmo nível em que a lista foi encontrada, não só no topo: em
  # notificações e conversas o `meta` mora dentro de `data`, e eu estava jogando
  # fora um total que a plataforma tinha dado. E a chave nem sempre é `count` —
  # conversas chamam de `all_count`.
  def total_de(dados)
    return nil unless dados.is_a?(Hash)

    meta = dados['meta']
    return meta['count'] || meta['all_count'] if meta.is_a?(Hash)

    interno = dados['payload'] || dados['data']
    interno.is_a?(Hash) ? total_de(interno) : nil
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

    cabe_no_item(achatado(sem_segredos(item)).select { |_campo, valor| identifica?(valor) })
  end

  # Teto por item, para um recurso gordo não comer a lista inteira. Achatar o
  # aninhado trouxe o nome do cliente na conversa — que é o ponto —, mas trouxe
  # junto o texto da última mensagem: a conversa foi de ~400 para ~1.975
  # caracteres, e sete de vinte e cinco ficavam de fora da lista.
  #
  # Quando o item estoura, os campos MAIS LONGOS saem primeiro. Continua sendo
  # corte por forma: campo longo é conteúdo, campo curto identifica. Nome,
  # status e identificador sobrevivem; o corpo da mensagem, não.
  MAX_TEXTO_DE_ITEM = 800

  def cabe_no_item(item)
    return item if JSON.generate(item).length <= MAX_TEXTO_DE_ITEM

    sobrando = item.dup
    # Quem sai primeiro é o que veio de DENTRO de um objeto aninhado, não o
    # campo mais longo. Só por tamanho, o nome de um contato — "Maria Aparecida
    # dos Santos Albuquerque de Oliveira Nascimento Filha" — saía antes de vinte
    # e cinco atributos curtos e irrelevantes. Medido: o nome sumia da lista.
    #
    # O campo de topo é a identidade do registro; o achatado é contexto que veio
    # junto. Dentro de cada grupo, o mais longo sai primeiro, e o nome do campo
    # desempata: `sort_by` no MRI não é estável, e sem desempate a mesma conta
    # responderia diferente em duas leituras.
    ordem = item.keys.sort_by do |campo|
      [campo.to_s.include?(CAMINHO_ACHATADO) ? 0 : 1, -"#{campo}#{item[campo]}".length, campo.to_s]
    end
    ordem.each do |campo|
      break if JSON.generate(sobrando).length <= MAX_TEXTO_DE_ITEM

      sobrando.delete(campo)
    end
    sobrando
  end

  # Nome de gente costuma morar aninhado. Numa conversa, quem é o cliente está
  # em `meta.sender.name`, e o corte por forma jogava o `meta` inteiro fora: a
  # lista de conversas chegava sem nome nenhum, só id e status — inútil para
  # "quais conversas eu tenho".
  #
  # Então os valores simples que estão a até dois níveis sobem para o topo, com
  # o caminho no nome (`meta.sender.name`). Continua sendo corte por forma: não
  # há lista de campos por recurso, e o que não é valor simples segue de fora.
  # O ponto marca de onde o valor veio: `meta.sender.name` nasceu aninhado.
  CAMINHO_ACHATADO = %(.).freeze
  NIVEIS_ACHATADOS = 2

  def achatado(item, nivel = 0)
    item.each_with_object({}) do |(campo, valor), plano|
      if valor.is_a?(Hash) && nivel < NIVEIS_ACHATADOS
        achatado(valor, nivel + 1).each { |interno, v| plano["#{campo}#{CAMINHO_ACHATADO}#{interno}"] = v }
      else
        plano[campo.to_s] = valor
      end
    end
  end

  # Vale em lista e em item único, e desce até o fim: na lista o Hash aninhado
  # cai por forma, mas no item único ele vai inteiro — e era ali que o
  # `provider_config` de uma caixa de WhatsApp levava a chave da API junto.
  # Segredo escondido dentro de um objeto continua sendo segredo.
  def sem_segredos(dados)
    case dados
    when Hash then dados.reject { |campo, _| segredo?(campo) }.transform_values { |valor| sem_segredos(valor) }
    when Array then dados.map { |valor| sem_segredos(valor) }
    else dados
    end
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
    # Total e corte NUNCA se excluem. A versão anterior devolvia o total e
    # engolia o aviso: com 25 conversas na conta e 18 cabendo, o modelo ouvia
    # "total: 25", listava 18 e ninguém sabia das outras 7. É o defeito original
    # — contar a amostra — voltando por outra porta.
    cortou = mostrados < na_pagina
    if total.present?
      return " (total nesta conta: #{total})" unless cortou

      return " (total nesta conta: #{total}, mas só #{mostrados} couberam aqui; " \
             'os outros ficaram de fora desta lista)'
    end

    if cortou
      return " (a plataforma entregou #{na_pagina} e mostrei #{mostrados}; o resto ficou de fora, " \
             'então NÃO afirme quantos são)'
    end

    # Aqui a lista veio inteira do jeito que a plataforma entregou, e ela não
    # disse quantos existem. Duas versões anteriores erraram nas duas pontas:
    # uma proibia responder (e o Guia se recusava a dizer quantas caixas a
    # pessoa tem), a outra MANDAVA afirmar (e ele dizia "25" para quem tinha 30,
    # porque a plataforma tinha paginado sem avisar).
    #
    # O certo é dizer o que se sabe — quantos vieram — sem mandar tratar isso
    # como o total da conta. Quem lê decide como dizer.
    " (a plataforma entregou #{mostrados} e estão todos acima; ela não informou o total, " \
      'então diga quantos vieram, sem afirmar que é tudo o que existe)'
  end
end
