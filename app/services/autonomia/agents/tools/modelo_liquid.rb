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
    template.render!(params, strict_variables: true, strict_filters: true, global_filter: filtro)
  rescue Liquid::Error
    raise
  rescue StandardError => e
    Rails.logger.warn("[autonomia][agent_tool] erro fora do Liquid no render original=#{e.class} em=#{e.backtrace&.first}")
    raise Liquid::InternalError, 'internal', cause: nil
  end

  # Recusa (`faixa_grande`) o modelo com `for` sobre faixa maior que FAIXA_MAXIMA ou montada com variável. Só lê a
  # árvore: nada é renderizado.
  def conferir_faixas!(template)
    perigosa = todos_os_nos(template.root).grep(Liquid::For).any? { |no| faixa_perigosa?(no.collection_name) }
    raise Autonomia::Agents::Tools::HttpExecutor::ValorRecusado, 'faixa_grande' if perigosa

    template
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
