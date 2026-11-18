# Cliente da base de Condições Gerais da SUSEP (a "Mia"), em agent.autonomia.site.
#
# A base tem as CGs vigentes das seguradoras, com busca e uma síntese que carimba `answer_status` e
# `grounded`. É isso que permite ao agente responder "o vidro traseiro está coberto?" sem inventar e
# sem escalar toda vez.
#
# USA SÓ O `/perguntar` (#3035). Até 15/11/2026 usava o `/query`, com o produto fixo em "Automóvel":
# pergunta de residencial, vida ou GAP sem ramo caía no contrato de carro ou voltava vazia. No
# `/perguntar` a própria API lê a pergunta com as palavras do cliente e escolhe a rota (consulta,
# comparativo, documentos), a seguradora e o produto — inclusive a marca irmã quando o produto está
# na outra empresa do grupo. Quem chama não escolhe nada disso.
#
# A CHAVE É A DA CONTA DO CLIENTE ("Sempre a chave de cada conta. Sempre!", Rodrigo). Toda chamada
# de modelo do pedido (roteador, busca, rerank, síntese) roda nela; sem chave, a API usaria a chave
# do servidor dela, e por isso aqui sem chave não há chamada. A API só aceita a chave no endereço
# (`?api_key=`, decisão do Rodrigo em 12/11/2026): a URL montada NUNCA vai para log nem para a
# mensagem de erro — os erros levam só o código HTTP e o código da API.
#
# AUTENTICAÇÃO DA API: segue aberta. `GENERAL_CONDITIONS_TOKEN` já é enviado quando presente, para
# que fechar a API mais tarde seja só definir a variável dos dois lados.
class Autonomia::Insurance::GeneralConditions::Client
  class Error < StandardError; end

  # A base não conhece essa seguradora (HTTP 404 `insurer_not_found`). É LACUNA DE COBERTURA, não
  # falha de infra: "não tenho o contrato dessa seguradora" ≠ "a consulta caiu".
  class InsurerNotFound < Error; end

  DEFAULT_BASE_URL = 'https://agent.autonomia.site'.freeze
  # Medido em 15/11/2026 no `/perguntar`: consulta 17s, comparativo de duas seguradoras 36,7s. O
  # turno inteiro tem 120s; 60s cobre a cauda do comparativo sem prender o resto.
  TIMEOUT_SECONDS = 60

  # Avisos que fazem a resposta valer só em parte: o modelo marcou parcial, não disse se resolve a
  # pergunta (o JSON veio sem o campo ou inválido), ou deixou escapar uma etiqueta interna no texto.
  PARTIAL_WARNINGS = %w[model_marked_partial llm_json_answers_question_missing llm_json_answers_question_invalid
                        internal_mark_in_answer].freeze

  # O que a síntese carimba, igual na consulta e em cada seguradora do comparativo.
  module Verdict
    # `answered` + `grounded`: a resposta se apoia em cláusula real.
    def usable?
      status == 'answered' && grounded
    end

    def partial?
      warnings.intersect?(PARTIAL_WARNINGS)
    end
  end

  # `resolved`: o nome da seguradora casou com alguma empresa da base. `notice` é o `resposta.aviso`
  # (marca irmã, seguradora sem o produto, produto trocado); `catalog`, os pares seguradora × produto
  # do catálogo; `coverage`, o que o comparativo deixou de fora (ver `comparison_coverage`).
  Answer = Struct.new(:route, :text, :status, :grounded, :warnings, :insurer, :resolved, :suggestions, :cited,
                      :notice, :documents, :comparisons, :catalog, :coverage, keyword_init: true) do
    include Verdict
  end

  # Uma seguradora dentro do comparativo: cada uma tem a sua síntese, com o seu próprio status.
  Comparison = Struct.new(:insurer, :text, :status, :grounded, :warnings, keyword_init: true) do
    include Verdict
  end

  # `pdf_url` só vem quando o PDF está guardado na base; `susep_url` vem em todo documento.
  Document = Struct.new(:insurer, :product, :process, :file_name, :pdf_url, :susep_url, keyword_init: true) do
    def link
      pdf_url.presence || susep_url.presence
    end
  end

  OPENAI_HOST = 'api.openai.com'.freeze

  # A chave da conta, ou nil. Só a do hook `crm_kanban_ai` (`source: :hook`): o resolvedor cai na da
  # instalação quando a conta não tem hook, e aqui isso não vale. Endpoint próprio também não serve:
  # a API manda a chave à OpenAI, e a de outro provedor voltaria 401.
  def self.account_key(account)
    credential = Crm::Ai::CredentialResolver.new(account: account).resolve
    return unless credential.is_a?(Hash) && credential[:source] == :hook
    return unless URI.parse(credential[:api_base].to_s).host == OPENAI_HOST

    credential[:api_key]
  rescue URI::InvalidURIError
    nil
  end

  def initialize(base_url: nil, token: nil)
    @base_url = (base_url || ENV.fetch('GENERAL_CONDITIONS_URL', DEFAULT_BASE_URL)).chomp('/')
    @token = token || ENV.fetch('GENERAL_CONDITIONS_TOKEN', nil)
  end

  # -> Answer. Levanta Error; quem chama é a ferramenta, que traduz para texto.
  def ask(question:, api_key:)
    raise Error, 'sem_chave' if api_key.blank?

    payload = post('/perguntar', { pergunta: question, include_evidence: false }, api_key)
    parse(payload['encaminhamento'].to_h, payload['resposta'].to_h)
  end

  private

  # Rotas: consulta, comparativo, documentos, catalogo e fora_do_escopo. Fora do escopo vem no formato
  # da consulta, com `answer_status: out_of_scope`.
  def parse(route_info, body)
    case route_info['rota'].to_s
    when 'comparativo' then comparison_answer(body)
    when 'documentos' then documents_answer(body)
    when 'catalogo' then catalog_answer(body)
    when 'fora_do_escopo' then query_answer('fora_do_escopo', body).tap { |answer| answer.status = 'out_of_scope' }
    else query_answer(route_info['rota'].to_s, body)
    end
  end

  def empty_answer(route)
    Answer.new(route: route, text: '', status: '', grounded: false, warnings: [], resolved: false, suggestions: [],
               cited: [], notice: {}, documents: [], comparisons: [], catalog: [], coverage: {})
  end

  # O nome que o corretor usa raramente é o da SUSEP ("Porto" vira "Porto Seguro"). A API devolve o
  # que resolveu em `interpreted`, e isso vai junto: o agente tem que dizer de QUAL seguradora é a regra.
  def query_answer(route, body)
    empty_answer(route).tap do |answer|
      answer.text = body['answer_text'].to_s.strip
      answer.status = body['answer_status'].to_s
      answer.grounded = body['grounded'] == true
      answer.warnings = Array(body['warnings']).map(&:to_s)
      add_insurer(answer, body)
      add_notices(answer, body)
    end
  end

  def add_insurer(answer, body)
    insurers = body.dig('interpreted', 'insurers')&.first.to_h
    answer.resolved = Array(insurers['resolved']).any?
    answer.insurer = Array(insurers['resolved']).first.presence || insurers['sent']
    answer.suggestions = Array(insurers['did_you_mean'])
  end

  # Os avisos que mudam o que o agente pode dizer: contratos citados e `resposta.aviso`.
  def add_notices(answer, body)
    answer.cited = Array(body.dig('contracts', 'cited'))
    answer.notice = body['aviso'].to_h
  end

  # No comparativo o status vem em cada seguradora (inclusive `no_context`: a busca não achou trecho dela).
  def comparison_answer(body)
    comparisons = Array(body['insurer_results']).map do |result|
      Comparison.new(insurer: result['insurer_name'].to_s, text: result['answer_text'].to_s.strip,
                     status: result['answer_status'].to_s, grounded: result['grounded'] == true,
                     warnings: Array(result['warnings']).map(&:to_s))
    end
    empty_answer('comparativo').tap do |answer|
      answer.comparisons = comparisons
      answer.coverage = comparison_coverage(body)
    end
  end

  # Quem ficou de fora do comparativo, e por quê. Sem isto o agente lê a lista como completa.
  #   - without_documents: a base não tem condição geral da seguradora para o produto (não é "não cobre");
  #   - left_out: ficaram fora do comparativo (`insurers_left_out:A; B`), não quer dizer sem documento;
  #   - truncated: a lista foi cortada (`insurers_truncated_from_X_to_Y`);
  #   - readings: que empresa representou cada nome. Formato: `insurer_name_resolved:<nome>=<empresa>`,
  #     às vezes seguido de `;also_compared=X|Y` e `;also_left_out=Z`; só o primeiro pedaço entra.
  def comparison_coverage(body)
    warnings = Array(body['warnings']).map(&:to_s)
    { without_documents: Array(body.dig('coverage', 'insurers_without_documents')).map(&:to_s),
      left_out: warning_values(warnings, 'insurers_left_out:').flat_map { |names| names.split(';').map(&:strip) },
      truncated: warnings.any? { |warning| warning.start_with?('insurers_truncated_from_') },
      readings: warning_values(warnings, 'insurer_name_resolved:').map { |reading| reading.split(';').first.to_s.split('=', 2) } }
  end

  def warning_values(warnings, prefix)
    warnings.select { |warning| warning.start_with?(prefix) }.map { |warning| warning.delete_prefix(prefix) }
  end

  def documents_answer(body)
    documents = Array(body['documents']).map do |doc|
      Document.new(insurer: doc['insurer'].to_s, product: doc['product'].to_s, process: doc['process_susep'].to_s,
                   file_name: doc['file_name'].to_s, pdf_url: doc['pdf_url'].to_s, susep_url: doc['url'].to_s)
    end
    empty_answer('documentos').tap { |answer| answer.documents = documents }
  end

  # O catálogo não tem síntese: o que responde "quem tem o produto X" são os pares de `availability`.
  # `totals` é da base inteira, não do filtro, e por isso não entra.
  def catalog_answer(body)
    pairs = Array(body['availability']).map { |pair| [pair['insurer'].to_s, pair['product'].to_s] }
    empty_answer('catalogo').tap { |answer| answer.catalog = pairs }
  end

  def post(path, body, api_key)
    response = HTTParty.post("#{@base_url}#{path}", query: { api_key: api_key }, body: body.to_json,
                                                    headers: headers, timeout: TIMEOUT_SECONDS)
    raise InsurerNotFound, 'insurer_not_found' if insurer_not_found?(response)
    raise Error, error_code(response) unless response.code == 200

    parsed = response.parsed_response
    raise Error, 'unexpected_payload' unless parsed.is_a?(Hash)

    parsed
  rescue Error
    raise
  rescue StandardError => e
    # Qualquer falha de rede, SSL ou JSON vira Error com SÓ a classe: a mensagem de algumas dessas
    # exceções traz o endereço, que leva a chave.
    raise Error, e.class.name
  end

  # Corpo real observado em 15/11/2026: o 404 vem com a rota dentro de `resposta`,
  # {"encaminhamento": {...}, "resposta": {"error": {"code": "insurer_not_found", ...}}}.
  def insurer_not_found?(response)
    return false unless response.code == 404

    response.parsed_response.to_h.dig('resposta', 'error', 'code') == 'insurer_not_found'
  rescue StandardError
    false
  end

  # "http_401_llm_auth_failed", "http_503_router_unavailable": o código da API ajuda o diagnóstico e
  # não carrega dado do cliente. A mensagem livre não entra.
  def error_code(response)
    detail = response.parsed_response.is_a?(Hash) ? response.parsed_response['detail'] : nil
    ["http_#{response.code}", (detail if detail.is_a?(String))].compact.join('_')
  rescue StandardError
    "http_#{response.code}"
  end

  def headers
    base = { 'Content-Type' => 'application/json', 'Accept' => 'application/json' }
    @token.present? ? base.merge('Authorization' => "Bearer #{@token}") : base
  end
end
