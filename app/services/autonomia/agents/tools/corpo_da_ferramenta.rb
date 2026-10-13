# O corpo da chamada HTTP de uma ferramenta, montado sem deixar o valor do modelo virar estrutura (#1425).
#
# O ESCAPE É NA SAÍDA de cada {{ }}, DEPOIS dos filtros (`global_filter` do Liquid): um `url_decode`
# ou `base64_decode` no modelo do corpo não desfaz o escape, e um filtro de texto (`upcase`, `truncate`)
# trabalha sobre o valor original. Cada tipo de corpo tem o seu escape:
#
# - JSON (Content-Type ausente ou com "json"): texto vai escapado para dentro de aspas; número e
#   sim/não vão como são. Uma sonda renderiza o corpo com cada texto trocado por um caractere que nunca
#   é JSON válido fora de aspas (`MARCA`): se a sonda não for JSON, há texto numa vaga sem aspas e o
#   corpo é recusado — o texto poderia abrir lista, objeto ou comentário. Vai pelo fio o JSON REGERADO
#   (`JSON.generate(JSON.parse(...))`): comentário do modelo do corpo nunca chega ao destino.
# - Formulário (`application/x-www-form-urlencoded`): cada valor vai codificado como campo
#   (`URI.encode_www_form_component`), e `&`/`=` vindos do modelo não abrem campo novo.
# - Qualquer outro tipo (XML, texto…): não há escape seguro conhecido. O corpo FIXO vai como foi escrito;
#   com {{ }}, é recusado (`corpo_sem_escape`).
#
# `literais` são os valores que o MODELO DO CORPO traz escritos (uma chave fixa, um código de conta):
# vêm da configuração, não do modelo, e o trecho de um erro não pode ecoá-los ao modelo.
class Autonomia::Agents::Tools::CorpoDaFerramenta
  Recusa = Autonomia::Agents::Tools::HttpExecutor::ValorRecusado
  MARCA = "\u{E000}".freeze
  FORMULARIO = 'application/x-www-form-urlencoded'.freeze

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
    else []
    end
  end

  # Mesma regra do `HttpExecutor`: sem Content-Type declarado, o executor manda `application/json`.
  def tipo
    declarado = Array(@tool.headers_config).find { |header| header['key'].to_s.casecmp?('content-type') }
    valor = declarado.to_h['value'].to_s.downcase
    return :json if declarado.nil? || valor.include?('json')

    valor.include?(FORMULARIO) ? :formulario : :outro
  end

  private

  def sem_corpo?
    @tool.request_body_template.to_s.blank? || @tool.http_method == 'GET'
  end

  def json
    JSON.parse(sonda)
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
      else MARCA
      end
    end)
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

  def texto_de(valor)
    valor.is_a?(Array) ? valor.join : valor.to_s
  end

  def renderizar(filtro)
    modelo.render(@params, strict_variables: true, strict_filters: true, global_filter: filtro)
  end

  def modelo
    @modelo ||= Liquid::Template.parse(@tool.request_body_template.to_s, error_mode: :strict)
  end
end
