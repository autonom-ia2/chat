# O encolhimento da resposta da plataforma, para ela caber onde vai ser lida
# (extraído da `Consulta` na issue #568).
#
# Mora separado porque são duas responsabilidades diferentes: a `Consulta`
# decide O QUE ler e faz a chamada com a permissão de quem perguntou; aqui se
# decide QUANTO disso cabe. Juntas, passavam de 175 linhas de código e qualquer
# mexida numa mexia na outra.
#
# O critério é sempre o mesmo, e é o do Rodrigo: **resposta certa e completa**.
# Cortar é o último recurso, e cortar calado é proibido — quem lê precisa saber
# que o que chegou é um pedaço, senão conta a amostra como se fosse o total.
class Autonomia::Guide::Resumo
  # Tetos medidos, não escolhidos no chute.
  #
  # São TETO, não custo fixo: uma conta com três caixas gasta ~1.700
  # caracteres. Só paga o tamanho quem tem o tamanho.
  MAX_ITENS = 100

  # 100.000, por decisão do Rodrigo em 21/09/2026. O critério que ele fixou não
  # é custo — a chave de IA é do cliente — e sim resposta certa e completa.
  # Quem lê por FERRAMENTA passa um teto bem menor (`GuiaLeitura::TETO`), porque
  # a saída de uma ferramenta tem limite próprio.
  MAX_TEXTO = 100_000

  # Dois mil, a pedido do Rodrigo em 21/09/2026, pelo mesmo critério: resposta
  # completa vale mais do que lista enxuta. Com 400, a listagem entregava nome e
  # status e jogava fora o que o cliente escreveu — quem perguntasse "o que
  # estão reclamando" recebia uma lista muda.
  MAX_TEXTO_DE_CAMPO = 2_000

  # Teto por item, para um recurso gordo não comer a lista inteira. Cinco mil,
  # por decisão do Rodrigo em 21/09/2026: oitocentos foi medido curto demais (um
  # card do CRM real dá 816 e perdia o nome do cliente, do funil e da caixa de
  # uma vez); cinco mil deixa o item vir praticamente inteiro.
  MAX_TEXTO_DE_ITEM = 5_000

  # Espaço reservado para a nota de contagem, que é escrita DEPOIS de saber
  # quantos itens couberam — e por isso não dá para medir antes. É o teto do
  # texto dela, com folga para os números.
  MARGEM_DA_NOTA = 250

  # Como cada recurso chama o total dele. Eram só `count` e `all_count`, e com
  # isso artigos, portais e mais seis telas diziam "não sei quantos" com o
  # número na mão — a plataforma informava, e eu não entendia a palavra.
  CHAVES_DE_TOTAL = %w[count all_count total_count articles_count portals_count].freeze

  # Segredo NUNCA sai daqui, em lista ou em item.
  #
  # O corte deste arquivo é por forma, e segredo é justamente o caso em que a
  # forma não denuncia nada: `hmac_token`, `imap_password`, `smtp_password` e o
  # `secret` de webhook são strings curtas, iguaizinhas a um nome de caixa. Iam
  # inteiros para o modelo. Aqui o nome é a única coisa que importa, e vale para
  # qualquer um dos 270 recursos.
  SEGREDOS = %w[
    secret hmac_token inbox_identifier
    password imap_password smtp_password
    token access_token auth_token refresh_token api_key apikey
    private_key client_secret signing_key webhook_secret
  ].freeze

  def initialize(corpo:, campos: nil, teto: MAX_TEXTO)
    @corpo = corpo
    @campos = campos
    @teto = teto
  end

  def texto
    resumir(@corpo, @campos, @teto)
  end

  private

  # Resposta de API é verbosa e cheia de campo que não ajuda a responder. Corta
  # para caber no contexto sem virar ruído — e sem inventar: o que sobra é o que
  # a API devolveu.
  def resumir(corpo, campos, teto)
    dados = JSON.parse(corpo.to_s)
    lista = lista_de(dados)
    return item_unico(lista, teto) unless lista.is_a?(Array)

    limpos = lista.map { |item| sem_segredos(item) }
    catalogo = campos.present? ? nil : catalogo_de_campos(limpos.first)
    # O orçamento é do TEXTO INTEIRO, e as notas fazem parte dele. Sem descontar
    # as duas, a resposta estoura o teto de saída da ferramenta e o `Bound`
    # corta o fim — justamente onde mora o total.
    catalogo ||= campos_inexistentes(limpos, campos)
    mostrados = cabem(escolhidos(limpos, campos), teto - catalogo.to_s.length - MARGEM_DA_NOTA)

    "#{JSON.generate(mostrados)}#{quantos(mostrados.size, lista.size, total_de(dados))}#{catalogo}"
  rescue JSON::ParserError
    corpo.to_s[0, teto]
  end

  # Com `campos`, o que foi pedido; sem, o que identifica o item.
  def escolhidos(limpos, campos)
    limpos.map { |item| campos.present? ? pedidos(item, campos) : enxuto(item) }
  end

  # Os campos que quem chamou pediu, e só eles. Sem filtro por forma: quem pede
  # `last_non_activity_message.content` quer o texto da mensagem, e cortá-lo por
  # ser longo seria desobedecer em silêncio. O teto por item continua valendo —
  # um campo sozinho não pode comer a lista.
  def pedidos(item, campos)
    cabe_no_item(achatado(item).slice(*Array(campos).map(&:to_s)))
  end

  # Campo pedido que o recurso não tem não pode sumir calado (#593). Medido em
  # 22/09/2026: pedindo `id` e `name` às caixas de um funil — que têm
  # `inbox.name`, não `name` —, cada item voltou só com `{"id":7}`, o id da
  # LIGAÇÃO. A caixa WhatsApp Comercial também tinha id 7, e o Guia afirmou a
  # um cliente que ela estava no funil errado.
  def campos_inexistentes(limpos, campos)
    return nil if limpos.empty?

    existentes = limpos.flat_map { |item| achatado(item).keys }.uniq
    ausentes = Array(campos).map(&:to_s) - existentes
    return nil if ausentes.empty?

    " [NOTA INTERNA, não repita: estes campos NÃO existem neste recurso e não vieram: #{ausentes.join(', ')}. " \
      "Os que existem são: #{existentes.join(', ')}. Não tire conclusão do que faltou: leia de novo com os nomes certos.]"
  end

  # O que mais existe neste recurso, para quem chamou poder pedir na próxima.
  # É isto que substitui a adivinhação: em vez de eu escolher os campos certos
  # para 270 recursos, cada um diz o que tem e quem leu a pergunta escolhe.
  def catalogo_de_campos(item)
    return nil if item.blank?

    nomes = achatado(item).keys
    return nil if nomes.blank?

    ' [NOTA INTERNA, não repita: cada item acima veio resumido. Os campos ' \
      "disponíveis neste recurso são: #{nomes.join(', ')}. Precisando de algum que não veio, " \
      'leia de novo passando `campos` — aí cabem mais itens na mesma resposta.]'
  end

  # O que não é lista é o detalhe de um item: vai inteiro, menos os segredos.
  # Se ainda assim estourar, o corte é por caractere e por isso PRECISA avisar —
  # calado, ele entrega ao modelo um JSON partido no meio que parece completo.
  def item_unico(dados, teto)
    texto = JSON.generate(sem_segredos(dados))
    return texto if texto.length <= teto

    "#{texto[0, teto]} (esta resposta foi cortada no meio; NÃO afirme totais nem trate a lista " \
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
    return CHAVES_DE_TOTAL.filter_map { |chave| meta[chave] }.first if meta.is_a?(Hash)

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

    cabe_no_item(achatado(item, so_identidade: true).select { |_campo, valor| identifica?(valor) })
  end

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
    # `ordem` é um Array de CHAVES, não um Hash. O `rubocop -A` já reescreveu
    # este laço para `each_key` uma vez, método que Array não tem: o crash
    # derrubou a leitura de conversas inteira e ficou escondido atrás de um
    # rescue genérico. Não deixe a autocorreção mexer aqui de novo.
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

  # O que se aproveita de um REGISTRO que veio embutido dentro de outro. Não é
  # uma lista de campos por recurso — é o que "identidade" quer dizer em
  # qualquer um dos 270: como esse registro se chama e como apontar para ele.
  IDENTIDADE = %w[id name title label email phone_number subject].freeze

  # Um objeto aninhado é uma de duas coisas, e a diferença entre elas custou a
  # resposta errada de 21/09/2026:
  #
  # - **invólucro** — `meta`, `additional_attributes`, `provider_config`. Não é
  #   registro de nada, só agrupa campos do próprio item. Os campos dele passam.
  # - **registro** — `meta.sender` (o cliente), `last_non_activity_message` (a
  #   última mensagem). Tem vida própria, e por isso tem `id`. Dele se aproveita
  #   só a identidade.
  #
  # Sem essa distinção, uma conversa vinha com a última mensagem INTEIRA colada
  # dentro — com o remetente dela, a conversa dela e o texto duplicado em dois
  # campos. Medido em produção: 2.700 caracteres por conversa, 61% deles vindos
  # desse único registro embutido. Vinte e cinco conversas viravam 67 mil
  # caracteres, e o modelo se perdia neles com o dado certo na mão.
  #
  # Quem quiser o que ficou de fora pede por `campos` — e aí vem sem filtro.
  def achatado(item, nivel = 0, so_identidade: false)
    item.each_with_object({}) do |(campo, valor), plano|
      if valor.is_a?(Hash) && nivel < NIVEIS_ACHATADOS
        interno = so_identidade ? so_o_que_identifica(valor) : valor
        achatado(interno, nivel + 1, so_identidade: so_identidade).each do |chave, v|
          plano["#{campo}#{CAMINHO_ACHATADO}#{chave}"] = v
        end
      else
        plano[campo.to_s] = valor
      end
    end
  end

  def so_o_que_identifica(objeto)
    registro?(objeto) ? objeto.slice(*IDENTIDADE) : objeto
  end

  # Tem `id` próprio = é um registro, não um invólucro. É o mesmo critério por
  # FORMA do resto do arquivo: nada de nome de campo por recurso.
  def registro?(objeto)
    objeto.key?('id')
  end

  # Vale em lista e em item único, e desce até o fim: na lista o Hash aninhado
  # cai por forma, mas no item único ele vai inteiro — e era ali que o
  # `provider_config` de uma caixa de WhatsApp levava a chave da API junto.
  # Segredo escondido dentro de um objeto continua sendo segredo.
  def sem_segredos(dados)
    case dados
    when Hash then limpo_de_cascas(dados.reject { |campo, _| segredo?(campo) })
    when Array then dados.map { |valor| sem_segredos(valor) }
    else dados
    end
  end

  # Tirar o segredo de dentro de um objeto deixava a casca: `{"config":{}}`,
  # `{"lista":[{},{}]}`. Não vaza nada, mas na leitura de UM item é token gasto
  # com objeto que não diz mais nada. Some junto com o que estava lá dentro.
  def limpo_de_cascas(dados)
    dados.each_with_object({}) do |(campo, valor), limpo|
      tratado = sem_segredos(valor)
      next if (tratado.is_a?(Hash) || tratado.is_a?(Array)) && tratado.empty? && valor.present?

      limpo[campo] = tratado
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
  def cabem(lista, teto)
    orcamento = teto
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
      return " [NOTA INTERNA, não repita: são #{total} no total desta conta.]" unless cortou

      return " [NOTA INTERNA, não repita: são #{total} no total, e só #{mostrados} couberam nesta " \
             'lista. Diga o total e que está mostrando uma parte.]'
    end

    if cortou
      return " [NOTA INTERNA, não repita: vieram #{na_pagina} e mostrei #{mostrados}; o resto ficou " \
             'de fora. NÃO afirme um total.]'
    end

    # Aqui a lista veio inteira do jeito que a plataforma entregou, e ela não
    # disse quantos existem. Duas versões anteriores erraram nas duas pontas:
    # uma proibia responder (e o Guia se recusava a dizer quantas caixas a
    # pessoa tem), a outra MANDAVA afirmar (e ele dizia "25" para quem tinha 30,
    # porque a plataforma tinha paginado sem avisar).
    #
    # O certo é dizer o que se sabe — quantos vieram — sem mandar tratar isso
    # como o total da conta. Quem lê decide como dizer.
    # A marca [NOTA INTERNA, não repita] existe porque o modelo estava PAPAGAIANDO
    # este texto na tela: a pessoa perguntava quantas caixas tinha e ouvia "a
    # consulta retornou 3; a plataforma não informou o total". Ela não fez
    # consulta nenhuma, fez uma pergunta — e "plataforma não informou" é a minha
    # encanação aparecendo na conversa dela.
    " [NOTA INTERNA, não repita: vieram #{mostrados} e estão todos aqui. Diga quantos são; se " \
      'achar que a conta pode ter mais, diga que podem existir outros fora desta lista.]'
  end
end
