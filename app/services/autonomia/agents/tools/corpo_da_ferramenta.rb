# O corpo da chamada HTTP de uma ferramenta, montado sem deixar o valor do modelo virar estrutura (#1425).
#
# O ESCAPE É NA SAÍDA de cada {{ }}, DEPOIS dos filtros (`global_filter` do Liquid): um `url_decode`
# ou `base64_decode` no modelo do corpo não desfaz o escape, e um filtro de texto (`upcase`, `truncate`)
# trabalha sobre o valor original. As tags aceitas e o `url_encode` final estão em `ModeloLiquid`. Cada
# tipo de corpo tem o seu escape:
#
# - JSON (Content-Type ausente, vazio ou com "json"): texto vai escapado para dentro de aspas; número e
#   sim/não vão como são. Uma sonda renderiza o corpo com cada texto trocado por um caractere que nunca
#   é JSON válido fora de aspas (`MARCA`). Numa vaga SEM aspas, o texto só vale se for um escalar JSON
#   (número, true, false, null): é o caso legítimo do tipo padrão da tela (texto) com `{"id": {{ id }}}`
#   e "4512", que funcionava antes; qualquer outro texto ali faria a sonda deixar de ser JSON, e o corpo
#   é recusado — ele poderia abrir lista, objeto ou comentário. Comentário (`/* */`, `//`) no modelo do
#   corpo também é recusado: uma {{ }} escondida nele não aparece na sonda. Vai pelo fio o JSON
#   REGERADO (`JSON.generate(JSON.parse(...))`). Número não finito (`1e999`) e texto com UTF-8 inválido
#   não têm forma JSON: o corpo é recusado, nunca uma exceção solta.
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
  Modelo = Autonomia::Agents::Tools::ModeloLiquid

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
    @utf8_invalido = false
    real = renderizar(method(:para_json))
    raise Recusa, 'corpo_json_invalido' if @utf8_invalido

    JSON.generate(JSON.parse(real))
  rescue JSON::JSONError, EncodingError
    raise Recusa, 'corpo_json_invalido'
  end

  # Roda DENTRO do render do Liquid, que troca qualquer exceção por um erro genérico: o UTF-8 inválido
  # é marcado aqui e recusado depois do render, com o código certo.
  def para_json(valor)
    case valor
    when nil, Numeric, true, false then valor
    else
      texto = texto_de(valor)
      return JSON.generate(texto)[1..-2] if texto.valid_encoding?

      @utf8_invalido = true
      ''
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
    valor.nil? || valor == true || valor == false || (valor.is_a?(Numeric) && valor.finite?)
  rescue JSON::JSONError, EncodingError
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
  rescue JSON::JSONError, EncodingError
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
    Modelo.texto_de(valor)
  end

  def renderizar(filtro)
    Modelo.renderizar(modelo, @params, filtro)
  end

  def modelo
    @modelo ||= Modelo.ler(@tool.request_body_template, recusa: 'corpo_sem_escape', sem_url_encode_final: tipo == :formulario)
  end
end
