# O TEXTO QUE VAI AO CLIENTE — duas funções, e a diferença entre elas é DE QUEM É O TEXTO.
#
#   `vetar`   roda sobre a frase que o MODELO escreveu no pedido, na LEITURA do parâmetro. Reprovar
#             ali não custa entrega nenhuma: existe uma constante nossa para cada papel, e a frase
#             reprovada recua para ela (`InsuranceQuote::Frases`). É por isso que as regras podem
#             ser severas.
#   `depurar` roda sobre o texto FINAL, já montado com as nossas constantes, as frases vetadas e os
#             dados que nós formatamos. Ali reprovar custaria a cotação do cliente, então ela NUNCA
#             descarta: conserta o que dá, registra alto e deixa passar.
#
# POR QUE A FRONTEIRA MUDOU DE LUGAR (entrega das frases do especialista, 12/09/2026). Até aqui a
# peneira morava na SAÍDA, em `Tools::Progress`, e DESCARTAVA a entrega inteira ao achar um caminho
# de campo. Ela nasceu contra o texto do CÓDIGO — em 08/09/2026 um cliente leu `insured.document` no
# WhatsApp —, e com o texto todo nosso ela nunca disparava. Descartar deixou de ser aceitável no
# instante em que uma entrega passou a ser "abertura + dezessete preços + aviso" numa string só: o
# handle já tinha avançado, as ofertas nunca mais eram reemitidas, e o cliente lia a frase de falha
# sobre dezessete seguradoras que a corretora pagou.
#
# AS DUAS SÃO FUNÇÕES PURAS DO TEXTO, e isso é requisito, não estilo: a mesma frase é lida pela
# ferramenta (com conexão), pelo motor (sem conexão, em `notify_start`) e pelo encerramento (sem
# agente). Vetar diferente em cada lugar daria textos diferentes para o mesmo papel — e a identidade
# de uma entrega É o texto (`ToolRun#delivery_token`), de que dependem a dedupe do publicador, o
# aceite e a idempotência do fecho.
module Autonomia::Agents::Tools::TextoAoCliente
  # Teto de UMA frase do modelo. Nenhum papel precisa de mais que isto, e é ele que mantém o texto
  # composto (abertura + preços + aviso) longe do corte de `Progress::MAX_DELIVERY_CHARS`.
  #
  # A FOLGA FOI MEDIDA, e está na auditoria de 12/09/2026 com os números: com as DUAS frases do
  # especialista no teto e o pior item que o código produz (86 caracteres — preço sem período, que
  # leva a ressalva inteira, com o nome de seguradora mais longo que o portal devolveu), o texto
  # composto chega a 2.089/3.000 nas 17 seguradoras que o portal real devolveu, e só alcança o corte
  # na 27ª. É folga medida sobre este teto; não é guarda, e o corte não avisa ninguém quando morde.
  MAX_FRASE = 350

  # Travessão e meia-risca. Decisão do CEO (12/09/2026): não vão ao texto que o cliente lê. Onde o
  # travessão separava colunas, quem compõe decide o substituto (dois pontos no item da lista,
  # vírgula no nome do arquivo); aqui, no texto já composto, ele vira hífen — conserto que não muda
  # o sentido de um nome que veio do portal.
  TRAVESSOES = /[—–]/
  HIFEN = '-'.freeze

  # A CRASE É A ARMADILHA DA INSTRUÇÃO DE AGENTE: o modelo copia o acento grave do manual para o
  # WhatsApp, e o cliente lê o marcador.
  CRASE = '`'.freeze

  # QUALQUER DÍGITO REPROVA — e é só isso que esta regra faz. A proibição do CEO é mais larga
  # (número, contagem, valor, prazo e nome de seguradora); o que a máquina cobre é a forma ESCRITA
  # EM ALGARISMO. `Chegaram três opções`, `volto em cinco minutos` e `a Porto cotou` passam por
  # aqui: quem as barra é o manual do especialista, não a peneira. Nenhum dos papéis precisa de
  # dígito, porque quem escreve valor em reais, período e quantidade é o código.
  DIGITO = /[0-9]/
  MOEDA = /R\$/i

  # FOLHA DO FORMULÁRIO: minúscula seguida de maiúscula DENTRO de uma palavra (`cpfCnpj`, `zipCode`,
  # `isZeroKm`, `valorMercado`). Não existe em prosa portuguesa, e é a assinatura da maioria dos
  # ~90 campos que o adapter põe no formulário do modelo.
  FOLHA_CAMELCASE = /\b[a-z]+[A-Z][A-Za-z]*\b/

  # OS GRUPOS DO FORMULÁRIO, que é a metade esquerda de um caminho de campo. Vêm dos dois lugares do
  # código que já os declaram — os rótulos de grupo do formulário de auto e os grupos que a entrada
  # monta —, mais os dois nomes do formulário dos outros dez ramos. Nenhum é digitado duas vezes.
  #
  # O QUE ISTO NÃO COBRE, dito inteiro: grupo que exista no `quote/schema` do adapter e não em
  # `Parametros::GRUPOS` (ele entra no formulário com rótulo genérico). A folha desse grupo ainda
  # reprova por `FOLHA_CAMELCASE` quando é camelCase, que é o caso da quase totalidade delas; o
  # caminho pontuado com folha de uma palavra só (`novogrupo.plate`) passa. Preferi a lista curta e
  # verdadeira a uma heurística de forma: a anterior — dois identificadores colados por um ponto —
  # comia `p.ex.`, `hub2you.ai` e `contato@corretora.com.br`.
  GRUPOS_DO_RAMO = %w[segurado configuracoes].freeze

  # A URL SAI ANTES DE OLHAR, e sem isto a redação MUTILA O COMPARATIVO. A reserva do comparativo é
  # a frase do especialista mais a URL que o portal gerou (`Comparativo#entrega_do_comparativo`), e
  # essa URL termina em `.../quotation.pdf` — `quotation` é grupo de `Parametros::GRUPOS`, então o
  # caminho de campo casa DENTRO do link e o cliente recebe uma aba que não abre. A `main` tinha
  # esta exclusão (`Progress::URL`) e ela se perdeu junto com a peneira antiga; é regressão, não
  # desenho novo. Vale só para `redigir`: em `vetar` o modelo não escreve link nenhum, e recuar ali
  # custa uma frase.
  URL = %r{https?://\S+}

  # VOCABULÁRIO DE SISTEMA. Os quatro primeiros são os que a instrução de aceite já proíbe ao modelo
  # (`Declaracao::ACEITA`) — ela nasceu porque o modelo devolveu ao cliente "a cotação está em
  # conferência e não há preços disponíveis neste momento"; os demais são o vocabulário da máquina.
  # Comparados sem acento e sem caixa, com fronteira de palavra: `\bapi\b` não casa dentro de
  # "rapida".
  VOCABULARIO_DE_SISTEMA = ['em conferencia', 'processando', 'em analise', 'nao ha dados disponiveis',
                            'payload', 'handle', 'token', 'endpoint', 'json', 'timeout', 'null', 'status'].freeze

  module_function

  # -> a frase aparada, ou nil quando ela não pode ir ao cliente. nil é RECUO, não erro: quem chama
  # publica a constante do papel.
  #
  # SÓ STRING. O schema `strict` declara texto, mas o valor chega pelo `arguments` guardado na linha
  # — e um `to_s` sobre um Hash publicaria a inspeção dele ao cliente, que foi o que esta spec pegou.
  def vetar(valor)
    return unless valor.is_a?(String)

    texto = valor.strip
    return if texto.empty? || texto.length > MAX_FRASE || proibido?(texto)

    texto
  end

  # As regras de CONTEÚDO, sobre a frase já aparada. Sete, e cada uma tem dono: o travessão e o
  # dígito são a decisão do CEO (a parte dela que se verifica por forma — ver `DIGITO`); o caminho
  # de campo e a folha camelCase são o incidente de 08/09/2026; a crase é o modelo copiando o acento
  # grave do manual; o vocabulário de sistema é o que `ACEITA` proíbe.
  def proibido?(texto)
    return true if texto.include?(CRASE)

    [TRAVESSOES, DIGITO, MOEDA, FOLHA_CAMELCASE, caminho_de_campo].any? { |padrao| texto.match?(padrao) } ||
      vocabulario_de_sistema?(texto)
  end

  # -> o texto pronto para publicar, ou nil quando não sobrou texto nenhum. NUNCA descarta por
  # conteúdo: apara, troca o travessão por hífen, redige o caminho de campo que tenha escapado e
  # corta no teto de quem chama.
  #
  # É IDEMPOTENTE, e isso é requisito: a ferramenta a roda para calcular a identidade da entrega e o
  # `Progress` a roda de novo sobre o mesmo texto. Uma segunda passada que mudasse o texto daria um
  # token gravado diferente do token publicado, e o fecho perguntaria por uma mensagem que nunca
  # existiu. `strip`, a troca do travessão, a redação (o `…` não casa com o padrão) e
  # `truncate_text` sobre uma string já no teto devolvem a mesma string.
  def depurar(valor, teto:)
    texto = valor.to_s.strip.gsub(TRAVESSOES, HIFEN)
    return if texto.empty?

    ::Autonomia::Agents::Config.truncate_text(redigir(texto), teto)
  end

  # Troca o caminho de campo pelo sinal de corte e registra — sem ecoar o que casou, que é dado de
  # dentro. Chegar aqui é bug NOSSO: o texto neste ponto é feito de constantes, frases já vetadas e
  # números que nós formatamos. FORA DAS URLs, sempre: ver `URL`.
  def redigir(texto)
    return texto unless texto.gsub(URL, ' ').match?(caminho_de_campo)

    Rails.logger.warn('[autonomia][tool] caminho de campo redigido em texto de cliente')
    texto.gsub(url_ou_caminho) { ::Regexp.last_match(:url) || ::Autonomia::Agents::Config::TRUNCATION_SUFFIX }
  end

  # UMA VARREDURA SÓ, COM A URL NA FRENTE da alternância: casando primeiro, ela consome o link
  # inteiro e o bloco o devolve intacto; o que casar pelo outro lado é caminho de campo de verdade,
  # e vira o sinal de corte. Apagar a URL antes e redigir depois não serviria — o texto que sai tem
  # de ser o de entrada com o caminho trocado, e o link precisa voltar no lugar exato.
  def url_ou_caminho
    @url_ou_caminho ||= /(?<url>#{URL.source})|#{caminho_de_campo.source}/
  end

  # `grupo.folha` com a folha começando em minúscula — a forma de `insured.document` e de
  # `segurado.cpfCnpj`. Exigir minúscula depois do ponto deixa passar o ponto final seguido de
  # maiúscula sem espaço ("o segurado.A apólice"), que é erro de digitação e não vazamento.
  def caminho_de_campo
    @caminho_de_campo ||= /\b(?:#{Regexp.union(grupos_do_formulario).source})\.[a-z][A-Za-z0-9]*/
  end

  def grupos_do_formulario
    @grupos_do_formulario ||= ::Autonomia::Insurance::Parametros::GRUPOS.keys |
                              ::Autonomia::Insurance::QuoteInput::GRUPOS_DE_AUTO |
                              GRUPOS_DO_RAMO
  end

  def vocabulario_de_sistema?(texto)
    sem_acento = ActiveSupport::Inflector.transliterate(texto).downcase

    VOCABULARIO_DE_SISTEMA.any? { |termo| sem_acento.match?(/\b#{Regexp.escape(termo)}\b/) }
  end
end
