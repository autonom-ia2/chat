# O corpo da chamada HTTP de uma ferramenta, montado sem deixar o valor do modelo virar estrutura (#1425).
#
# O ESCAPE É NA SAÍDA de cada {{ }}, DEPOIS dos filtros (`global_filter` do Liquid): um `url_decode`
# ou `base64_decode` no modelo do corpo não desfaz o escape, e um filtro de texto (`upcase`, `truncate`)
# trabalha sobre o valor original. O `global_filter` só vale para {{ }} (e `echo`): por isso o modelo do
# corpo só aceita as tags de `NOS_PERMITIDOS` — `cycle`, por exemplo, escreve o valor cru, e `capture`
# escaparia duas vezes. Cada tipo de corpo tem o seu escape:
#
# - JSON (Content-Type ausente, vazio ou com "json"): texto vai escapado para dentro de aspas; número e
#   sim/não vão como são. Uma sonda renderiza o corpo com cada texto trocado por um caractere que nunca
#   é JSON válido fora de aspas (`MARCA`). Numa vaga SEM aspas, o texto só vale se for um escalar JSON
#   (número, true, false, null): é o caso legítimo do tipo padrão da tela (texto) com `{"id": {{ id }}}`
#   e "4512", que funcionava antes; qualquer outro texto ali faria a sonda deixar de ser JSON, e o corpo
#   é recusado — ele poderia abrir lista, objeto ou comentário. Comentário (`/* */`, `//`) no modelo do
#   corpo também é recusado: uma {{ }} escondida nele não aparece na sonda. Vai pelo fio o JSON
#   REGERADO (`JSON.generate(JSON.parse(...))`).
# - Formulário (`application/x-www-form-urlencoded`): cada valor vai codificado como campo
#   (`URI.encode_www_form_component`), e `&`/`=` vindos do modelo não abrem campo novo. Um
#   `| url_encode` já escrito no fim da variável sai da lista de filtros: codifica uma vez só.
# - Qualquer outro tipo (XML, texto…): não há escape seguro conhecido. O corpo FIXO vai como foi escrito;
#   com {{ }}, é recusado (`corpo_sem_escape`).
#
# `literais` são os valores que o MODELO DO CORPO traz escritos (uma chave fixa, um código de conta):
# vêm da configuração, não do modelo; o `TrechoHigienizado` oculta os que têm cara de credencial.
class Autonomia::Agents::Tools::CorpoDaFerramenta
  Recusa = Autonomia::Agents::Tools::HttpExecutor::ValorRecusado
  MARCA = "\u{E000}".freeze
  FORMULARIO = 'application/x-www-form-urlencoded'.freeze
  NOS_PERMITIDOS = [
    String, Liquid::Document, Liquid::BlockBody, Liquid::Variable, Liquid::Echo, Liquid::If, Liquid::Unless,
    Liquid::For, Liquid::Assign, Liquid::Raw, Liquid::Comment
  ].freeze

  def initialize(tool:, params:)
    @tool = tool
    @params = params
  end

  # -> String para o fio, ou nil sem corpo.
  def texto
    return if sem_corpo?

    case tipo
    when :json then json
    when :formulario then renderizar(->(valor) { valor.nil? ? nil : URI.encode_www_form_component(texto_de(valor)) })
    else fixo
    end
  end

  def literais
    return [] if sem_corpo?

    case tipo
    when :json then literais_do_json
    when :formulario then literais_do_formulario
    else literais_do_fixo
    end
  end

  # Mesma regra do `HttpExecutor#request_headers`: Content-Type ausente ou vazio vira `application/json`.
  def tipo
    declarado = Array(@tool.headers_config).find do |header|
      header['key'].to_s.casecmp?('content-type') && header['value'].to_s.strip.present?
    end
    valor = declarado.to_h['value'].to_s.downcase
    return :json if declarado.nil? || valor.include?('json')

    valor.include?(FORMULARIO) ? :formulario : :outro
  end

  private

  def sem_corpo?
    @tool.request_body_template.to_s.blank? || @tool.http_method == 'GET'
  end

  def json
    teste = sonda
    raise Recusa, 'corpo_json_invalido' if com_comentario?(teste)

    JSON.parse(teste)
    JSON.generate(JSON.parse(renderizar(method(:para_json))))
  rescue JSON::ParserError
    raise Recusa, 'corpo_json_invalido'
  end

  def para_json(valor)
    case valor
    when nil, Numeric, true, false then valor
    else JSON.generate(texto_de(valor))[1..-2]
    end
  end

  def sonda
    renderizar(lambda do |valor|
      case valor
      when nil, true, false then valor
      when Numeric then 0
      else escalar_json?(texto_de(valor)) ? 0 : MARCA
      end
    end)
  end

  # Texto que, sozinho, é um escalar JSON: número, true, false ou null. Sem "/", que abriria comentário.
  def escalar_json?(texto)
    return false if texto.include?('/')

    valor = JSON.parse(texto)
    valor.nil? || valor == true || valor == false || valor.is_a?(Numeric)
  rescue JSON::ParserError
    false
  end

  # Há "/" fora de string na sonda? Só o modelo do corpo o põe lá: na sonda, todo valor do modelo é
  # MARCA (dentro de aspas), 0, true, false ou vazio.
  def com_comentario?(texto)
    dentro = false
    escapado = false
    texto.each_char do |caractere|
      if dentro
        escapado, dentro = fim_de_string(caractere, escapado)
      elsif caractere == '"'
        dentro = true
      elsif caractere == '/'
        return true
      end
    end
    false
  end

  # -> [escapado?, ainda dentro da string?]
  def fim_de_string(caractere, escapado)
    return [false, true] if escapado
    return [true, true] if caractere == '\\'

    [false, caractere != '"']
  end

  def fixo
    usou = false
    corpo = renderizar(lambda do |valor|
      usou = true
      valor
    end)
    raise Recusa, 'corpo_sem_escape' if usou

    corpo
  end

  def literais_do_json
    folhas(JSON.parse(sonda)).flat_map do |folha|
      next folha.split(MARCA) if folha.is_a?(String)

      folha.is_a?(Numeric) ? [folha.to_s] : []
    end
  rescue JSON::ParserError
    []
  end

  def folhas(valor)
    case valor
    when Hash then valor.values.flat_map { |item| folhas(item) }
    when Array then valor.flat_map { |item| folhas(item) }
    else [valor]
    end
  end

  def literais_do_formulario
    URI.decode_www_form(renderizar(->(_valor) {})).map(&:last)
  rescue ArgumentError
    []
  end

  # O corpo fixo (XML, texto) em pedaços, pelos mesmos separadores do `TrechoHigienizado`.
  def literais_do_fixo
    separadores = Autonomia::Agents::Tools::TrechoHigienizado::SEPARADORES
    fixo.each_char.chunk_while { |a, b| separadores.exclude?(a) && separadores.exclude?(b) }
        .map(&:join).reject { |pedaco| separadores.include?(pedaco) }
  end

  def texto_de(valor)
    valor.is_a?(Array) ? valor.join : valor.to_s
  end

  def renderizar(filtro)
    modelo.render(@params, strict_variables: true, strict_filters: true, global_filter: filtro)
  end

  def modelo
    @modelo ||= conferido(Liquid::Template.parse(@tool.request_body_template.to_s, error_mode: :strict))
  end

  # Só as tags de `NOS_PERMITIDOS`; no formulário, o `url_encode` final de cada variável sai (o escape
  # do formulário já codifica).
  def conferido(template)
    nos = todos_os_nos(template.root)
    raise Recusa, 'corpo_sem_escape' unless nos.all? { |no| NOS_PERMITIDOS.any? { |classe| no.instance_of?(classe) } }

    sem_url_encode_final(nos) if tipo == :formulario
    template
  end

  def todos_os_nos(raiz)
    filhos = raiz.respond_to?(:nodelist) ? Array(raiz.nodelist) : []
    [raiz] + filhos.flat_map { |filho| todos_os_nos(filho) }
  end

  def sem_url_encode_final(nos)
    nos.grep(Liquid::Variable).each do |variavel|
      variavel.filters = variavel.filters[0..-2] if variavel.filters.last&.first == 'url_encode'
    end
  end
end
