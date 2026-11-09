# O QUE NUNCA PODE APARECER NA RESPOSTA DE UMA CHAMADA HTTP DA FERRAMENTA (#1425), saído do `HttpExecutor` (#1430):
# o trecho do 4xx passa pelas regras inteiras (`higienizar`); a resposta 2xx da consulta em segundo plano, que fica
# gravada na execução e é mostrada ao modelo e a quem atende, só pelos segredos do cadastro (`mascarar`).
#
# `endereco` é o renderizador do executor (`HttpExecutor#render_template`): o endereço do cadastro com cada {{ }} vazio.
class Autonomia::Agents::Tools::SegredosDaChamada
  # O nome do parâmetro da query que é credencial, comparado inteiro (`casecmp?`, sem o `[]` do fim): a query não tem o
  # flag `secret`. A mesma lista recusa senha no link (`SegredoDaFerramenta`) e está no painel (`utils/ferramentas.js`).
  NOMES_DE_CREDENCIAL = %w[token api_key apikey api_token key secret client_secret password senha pwd access_token auth_token
                           access_key private_token hapikey x-api-key authorization].freeze
  CABECALHOS_DE_AUTENTICACAO = %w[authorization proxy-authorization].freeze

  def self.credencial?(nome)
    sem_colchetes = nome.to_s.delete_suffix('[]')
    NOMES_DE_CREDENCIAL.any? { |credencial| credencial.casecmp?(sem_colchetes) }
  end

  def initialize(tool:, headers:, corpo:, endereco:)
    @tool = tool
    @headers = headers
    @corpo = corpo
    @endereco = endereco
  end

  # O texto pelas regras do `TrechoHigienizado`, cortado em `limite`.
  def higienizar(texto, limite:, cortado: false)
    Autonomia::Agents::Tools::TrechoHigienizado.new(texto, segredos: segredos, literais: literais_do_cadastro, limite: limite,
                                                           cortado: cortado).to_s
  end

  # Só as CREDENCIAIS do cadastro (`credenciais`), em todas as formas, e só o valor inteiro (`TrechoHigienizado#mascarado`).
  # O resto da resposta é dado do negócio e chega inteiro, como no síncrono: o "ativo" de `?status=ativo` não esconde
  # o "INATIVO" da resposta, nem o `1000` de `?limite=1000` o "1000,00", nem o UUID de `?pedido=` o mesmo UUID.
  def mascarar(texto)
    Autonomia::Agents::Tools::TrechoHigienizado.new(texto, segredos: credenciais, limite: nil).mascarado
  end

  private

  # SEGREDO FORTE, sempre oculto: os valores de cabeçalho (menos os automáticos) em todas as formas
  # de autenticação, o usuário e a senha do endereço (e o Basic que o SafeFetch monta com eles) e os
  # valores da query do cadastro — chave em query pode ser só letras, e aí não tem "cara" nenhuma.
  def segredos
    cabecalhos = Array(@headers).reject { |key, _| %w[content-type accept].include?(key.to_s.downcase) }.map(&:last)
    cabecalhos.flat_map { |valor| formas_de_autenticacao(valor) } + usuario_e_senha + valores_da_query
  end

  # "Bearer x" -> o valor e x; "Basic b64" -> também o base64 decodificado ("usuario:senha"), o
  # usuário e a senha.
  def formas_de_autenticacao(valor)
    esquema, token = valor.to_s.split(' ', 2)
    return [valor] if token.blank?

    token = token.strip
    formas = [valor, token]
    esquema.casecmp?('basic') ? formas + basic_decodificado(token) : formas
  end

  # CREDENCIAL DO CADASTRO, pelo que o cadastro diz, sem heurística de formato nem pedaço de nome: o cabeçalho marcado
  # `secret` (`Tool#headers_config`, o mesmo flag do `tools_controller#segredo_guardado`), o valor de `Authorization` e
  # `Proxy-Authorization`, o usuário e a senha do endereço, e o parâmetro da query (que não tem o flag) cujo nome é,
  # inteiro, um da lista curta (`NOMES_DE_CREDENCIAL`, `casecmp?`): `keyword` e `author` não são credencial.
  def credenciais
    guardados = Array(@tool.headers_config).select { |item| ActiveModel::Type::Boolean.new.cast(item['secret']) }.map { |item| item['key'].to_s }
    cabecalhos = Array(@headers).select { |nome, _| cabecalho_de_credencial?(nome, guardados) }.map(&:last)
    cabecalhos.flat_map { |valor| formas_de_autenticacao(valor) } + usuario_e_senha + credenciais_da_query
  end

  def cabecalho_de_credencial?(nome, guardados)
    (CABECALHOS_DE_AUTENTICACAO + guardados).any? { |credencial| credencial.casecmp?(nome.to_s) }
  end

  def credenciais_da_query
    uri = endereco_do_cadastro
    return [] unless uri

    pares = URI.decode_www_form(uri.query.to_s)
    pares.select { |nome, _| self.class.credencial?(nome) }.map(&:last)
  rescue ArgumentError
    []
  end

  def basic_decodificado(token)
    texto = Base64.strict_decode64(token).force_encoding(Encoding::UTF_8)
    texto.valid_encoding? ? [texto, *texto.split(':', 2)] : []
  rescue ArgumentError
    []
  end

  # LITERAL DO CADASTRO (pedaços do caminho e valores do corpo): o `TrechoHigienizado` só
  # o oculta quando ele tem cara de credencial — "clientes" ou "ativo" continuam legíveis no erro.
  def literais_do_cadastro
    uri = endereco_do_cadastro
    caminho = uri ? uri.path.to_s.split('/').map { |parte| URI.decode_www_form_component(parte) } : []
    caminho + literais_do_corpo
  rescue ArgumentError
    literais_do_corpo
  end

  def usuario_e_senha
    uri = endereco_do_cadastro
    return [] unless uri

    crus = [uri.user, uri.password].compact
    partes = crus.map { |parte| URI.decode_www_form_component(parte) }
    return crus + partes if uri.user.blank?

    crus + partes + [Base64.strict_encode64("#{partes.first}:#{partes.second}")]
  rescue ArgumentError
    []
  end

  def valores_da_query
    uri = endereco_do_cadastro
    uri ? URI.decode_www_form(uri.query.to_s).map(&:last) : []
  rescue ArgumentError
    []
  end

  # O endereço com cada {{ }} vazio: sobra só o que está escrito no cadastro.
  def endereco_do_cadastro
    @endereco_do_cadastro ||= URI.parse(@endereco.call(@tool.endpoint_url.to_s, global_filter: ->(_valor) {}))
  rescue URI::InvalidURIError, Liquid::Error
    nil
  end

  def literais_do_corpo
    @corpo.literais
  rescue Autonomia::Agents::Tools::HttpExecutor::ValorRecusado, Liquid::Error
    []
  end
end
