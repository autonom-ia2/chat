# A leitura de um modelo Liquid da ferramenta HTTP que recebe valor do modelo de IA — corpo e endereço
# (#1425). O escape é na SAÍDA de cada {{ }}, pelo `global_filter`, que o Liquid só aplica em {{ }} e
# `echo`. Por isso só entram as tags de `NOS_PERMITIDOS`: `cycle` escreve o valor cru, e `capture` e
# `assign` escapariam duas vezes (o `global_filter` roda também dentro do `assign`). Com
# `sem_url_encode_final`, o `| url_encode` escrito no fim de uma variável (ou de um `echo`) sai da lista
# de filtros, porque o escape da posição já codifica — e codificar duas vezes muda o valor.
module Autonomia::Agents::Tools::ModeloLiquid
  NOS_PERMITIDOS = [
    String, Liquid::Document, Liquid::BlockBody, Liquid::Variable, Liquid::Echo, Liquid::If, Liquid::Unless,
    Liquid::For, Liquid::Raw, Liquid::Comment
  ].freeze
  # #1430 (revisão adversarial): o Liquid faz `to_a` da faixa de um `for` antes da primeira volta. `(1..2000000000)`
  # pede ~16 GB e derruba o processo; faixa com o que o agente preenche (`(1..n)`) pode virar isso. Até esta, vale.
  FAIXA_MAXIMA = 1000
  # Revisão do delta do #1430: sem faixa grande o modelo ainda cresce (texto que dobra a cada `assign`, `for` aninhados).
  # Todo render da ferramenta para ao passar destes limites (`Liquid::MemoryError`). Bem acima do uso real: a resposta do
  # sistema já é cortada em 256 KB, e o recorte de uma lista de centenas de itens fica longe do teto de nós.
  LIMITES = { render_score_limit: 100_000, render_length_limit: 1_000_000, assign_score_limit: 1_000_000 }.freeze
  # Tester do #1430 (B11): os limites acima contam nós e bytes, não o trabalho de um filtro — `split` de um texto grande a
  # cada volta gastava 5 s de CPU sem tocar em nenhum. Todo render tem prazo, conferido a cada nó e a cada volta. O
  # recorte de 500 itens leva milissegundos.
  PRAZO = 1.0

  # Os LIMITES do Liquid mais o PRAZO. O Liquid zera os contadores (`reset`) no começo de cada render: o prazo conta dali.
  class LimitesComPrazo < Liquid::ResourceLimits
    def reset
      super
      @prazo = Process.clock_gettime(Process::CLOCK_MONOTONIC) + PRAZO
    end

    def increment_render_score(amount)
      super
      conferir_prazo
    end

    def increment_write_score(output)
      super
      conferir_prazo
    end

    private

    def conferir_prazo
      raise_limits_reached if Process.clock_gettime(Process::CLOCK_MONOTONIC) > @prazo
    end
  end
  REPETEM = [Liquid::For, Liquid::TableRow].freeze

  # Revisão do delta (2ª): `{% assign n = n | times: n %}` em volta dobra o tamanho do número a cada volta, sem escrever
  # nada nem contar no `assign_score` — 30 voltas são segundos de CPU e memória sem teto. Estes filtros substituem os do
  # Liquid e param com `Liquid::MemoryError` quando o número inteiro passa de DIGITOS_MAXIMOS dígitos (preço, quantidade
  # e soma de lista ficam muito abaixo). `plus` e `minus` crescem devagar, mas entram para fechar a conta.
  module ContaLimitada
    DIGITOS_MAXIMOS = 30
    TETO = 10**DIGITOS_MAXIMOS

    %i[times plus minus].each do |filtro|
      define_method(filtro) do |input, operand|
        resultado = super(input, operand)
        raise Liquid::MemoryError, 'Memory limits exceeded' if resultado.is_a?(Integer) && resultado.abs >= TETO

        resultado
      end
    end
  end
  FILTROS = [ContaLimitada].freeze

  module_function

  # -> Liquid::Template; levanta `HttpExecutor::ValorRecusado` com `recusa` se usar tag fora da lista.
  def ler(texto, recusa:, sem_url_encode_final: false)
    template = conferir_faixas!(Liquid::Template.parse(texto.to_s, error_mode: :strict))
    nos = todos_os_nos(template.root)
    permitido = nos.all? { |no| NOS_PERMITIDOS.any? { |classe| no.instance_of?(classe) } }
    raise Autonomia::Agents::Tools::HttpExecutor::ValorRecusado, recusa unless permitido

    tirar_url_encode_final(nos) if sem_url_encode_final
    template
  end

  # `render!`, e não `render`: o Liquid engole o erro de render e escreve "Liquid error: ..." cru no texto,
  # sem passar pelo escape (#1444). Assim o erro sobe como `Liquid::Error` (variável ou chave que não
  # existe vira `undefined_variable`), o `HttpExecutor` recusa e nada é enviado. O `render!` relança a
  # exceção ORIGINAL quando ela não é do Liquid (um filtro que levanta `ArgumentError`), e ela escaparia do
  # tratamento da ferramenta: vira `Liquid::InternalError`, que o executor recusa como as outras. A classe original e a
  # linha onde quebrou vão para o log, sem a mensagem, que pode ter valor da conversa: um defeito nosso num filtro não
  # some no código. `cause: nil` para a mensagem também não seguir pendurada no erro novo.
  def renderizar(template, params, filtro)
    template.render!(contexto(params), strict_variables: true, strict_filters: true, global_filter: filtro, filters: FILTROS)
  rescue Liquid::Error
    raise
  rescue StandardError => e
    Rails.logger.warn("[autonomia][agent_tool] erro fora do Liquid no render original=#{e.class} em=#{e.backtrace&.first}")
    raise Liquid::InternalError, 'internal', cause: nil
  end

  # O recorte da resposta usa `render` (sem !): variável que falta fica vazia. Devolve nil quando um limite parou o
  # modelo — o `render` escreve esse erro no texto, e o agente não pode receber pedaço.
  def recortar(template, dados)
    limites = contexto(dados)
    saida = template.render(limites, strict_variables: false, strict_filters: true, filters: FILTROS)
    saida unless limites.resource_limits.reached? || template.errors.any?(Liquid::MemoryError)
  end

  def contexto(dados)
    Liquid::Context.build(environments: dados, resource_limits: LimitesComPrazo.new(LIMITES))
  end

  # Recusa (`faixa_grande`) o modelo com faixa maior que FAIXA_MAXIMA ou montada com variável EM QUALQUER LUGAR — `for`,
  # `assign`, filtro, condição (tester do #1430: guardada num `assign`, ela passava): o Liquid monta o array da faixa
  # inteira antes de qualquer limite contar. Recusa também `for`/`tablerow` sem nada dentro: o limite de render soma os nós
  # do corpo a cada volta, e corpo vazio soma zero (5 milhões de voltas em segundos). Só lê a árvore, pelo visitante do
  # próprio Liquid: nada é renderizado. Os LIMITES e o PRAZO vêm no contexto de cada render (`contexto`).
  def conferir_faixas!(template)
    raise Autonomia::Agents::Tools::HttpExecutor::ValorRecusado, 'faixa_grande' if faixa_perigosa_no?(template) || repete_sem_corpo?(template)

    template
  end

  def faixa_perigosa_no?(template)
    faixas = []
    Liquid::ParseTreeVisitor.for(template.root).add_callback_for(Range, Liquid::RangeLookup) { |faixa| faixas << faixa }.visit
    faixas.any? { |faixa| faixa_perigosa?(faixa) }
  end

  # No `for`, `nodelist` são os blocos (o corpo e o `else`); no `tablerow`, já é o corpo. O Liquid tira do corpo o texto
  # só de espaços.
  def repete_sem_corpo?(template)
    todos_os_nos(template.root).any? do |no|
      next no.nodelist.first.nodelist.empty? if no.instance_of?(Liquid::For)

      no.instance_of?(Liquid::TableRow) && no.nodelist.empty?
    end
  end

  # Para o cadastro: o texto tem faixa perigosa? Modelo que nem abre fica para a validação de cada campo.
  def faixa_grande?(texto)
    conferir_faixas!(Liquid::Template.parse(texto.to_s, error_mode: :strict))
    false
  rescue Autonomia::Agents::Tools::HttpExecutor::ValorRecusado
    true
  rescue Liquid::Error
    false
  end

  def faixa_perigosa?(colecao)
    return true if colecao.is_a?(Liquid::RangeLookup)

    colecao.is_a?(Range) && colecao.size.to_i > FAIXA_MAXIMA
  end

  # Há {{ }} ou {% %} no texto?
  def variavel?(texto)
    texto.to_s.include?('{{') || texto.to_s.include?('{%')
  end

  def texto_de(valor)
    valor.is_a?(Array) ? valor.join : valor.to_s
  end

  def todos_os_nos(raiz)
    filhos = raiz.respond_to?(:nodelist) ? Array(raiz.nodelist) : []
    [raiz] + filhos.flat_map { |filho| todos_os_nos(filho) }
  end

  # O `echo` carrega a variável dele em `#variable`, fora da árvore de nós.
  def tirar_url_encode_final(nos)
    (nos.grep(Liquid::Variable) + nos.grep(Liquid::Echo).map(&:variable)).each do |variavel|
      variavel.filters = variavel.filters[0..-2] if variavel.filters.last&.first == 'url_encode'
    end
  end
end
