# Cliente da base de Condições Gerais da SUSEP (a "Mia"), em agent.autonomia.site.
#
# A base tem as CGs vigentes das seguradoras — 5.182 processos cobertos do alvo, com busca vetorial
# e uma síntese que carimba `answer_status` e `grounded`. É isso que permite ao agente responder
# "o vidro traseiro está coberto?" sem inventar e sem escalar toda vez.
#
# O QUE ESTA CLASSE NÃO FAZ, de propósito:
#   - não usa `/catalog`: são ~163 KB por chamada, mais contexto do que o turno inteiro;
#   - não usa as rotas `/operator-*`: são de ESCRITA (aceitar documento, trocar baseline) e não têm
#     nada a ver com atender cliente. Ferramenta de agente só lê.
#
# AUTENTICAÇÃO: a API ainda está aberta (decisão do PO em 04/09/2026 — ligar primeiro, fechar
# depois). `GENERAL_CONDITIONS_TOKEN` já é enviado quando presente, para que fechar a API mais tarde
# seja só definir a variável dos dois lados, sem tocar neste código.
class Autonomia::Insurance::GeneralConditions::Client
  class Error < StandardError; end

  # A base não conhece essa seguradora (HTTP 404 `insurer_not_found`). É LACUNA DE COBERTURA, não
  # falha de infra, e o agente precisa dizer coisas diferentes: "não tenho o contrato dessa
  # seguradora" ≠ "a consulta caiu". Medido em 04/09/2026 com um nome inventado.
  class InsurerNotFound < Error; end

  DEFAULT_BASE_URL = 'https://agent.autonomia.site'.freeze
  # Medido em 04/09/2026: `/query` restrito a uma seguradora levou 10,1s; a memória do projeto
  # registra até 12s. 45s dá folga para a cauda sem prender o turno, que tem 120s no total.
  TIMEOUT_SECONDS = 45
  # Quantos trechos a busca vetorial recupera. Acima disso a síntese descarta por orçamento de
  # contexto (`context_budget_exhausted` apareceu já com 10) — pedir mais só gasta.
  DEFAULT_TOP_K = 10

  Answer = Struct.new(:text, :status, :grounded, :insurer, :suggestions, keyword_init: true) do
    # A síntese carimba `answered` + `grounded` quando a resposta se apoia em cláusula real.
    # Qualquer outra combinação é material insuficiente — e aí a ferramenta prefere dizer que não
    # sabe a entregar texto que parece resposta.
    def usable?
      status == 'answered' && grounded
    end
  end

  def initialize(base_url: nil, token: nil)
    @base_url = (base_url || ENV.fetch('GENERAL_CONDITIONS_URL', DEFAULT_BASE_URL)).chomp('/')
    @token = token || ENV.fetch('GENERAL_CONDITIONS_TOKEN', nil)
  end

  # -> Answer. Levanta Error; quem chama é a ferramenta, que traduz para texto.
  def query(question:, insurer:, product: nil, top_k: DEFAULT_TOP_K)
    body = { query: question, insurer_name: insurer, top_k: top_k, include_evidence: false }
    body[:insurance_type] = product if product.present?
    parse(post('/query', body))
  end

  private

  # O nome que o corretor usa raramente é o nome da SUSEP: "Bradesco" precisa virar "Bradesco
  # Seguros (Auto/RE)". A própria API resolve e devolve o que resolveu em `interpreted`, então não há
  # uma segunda chamada — mas o que ela resolveu vai junto na resposta, porque o agente tem que
  # dizer de QUAL seguradora é a regra que está citando.
  def parse(payload)
    insurers = payload.dig('interpreted', 'insurers')&.first.to_h
    Answer.new(
      text: payload['answer_text'].to_s.strip,
      status: payload['answer_status'].to_s,
      grounded: payload['grounded'] == true,
      insurer: Array(insurers['resolved']).first.presence || insurers['sent'],
      suggestions: Array(insurers['did_you_mean'])
    )
  end

  def post(path, body)
    response = HTTParty.post("#{@base_url}#{path}", body: body.to_json, headers: headers,
                                                    timeout: TIMEOUT_SECONDS)
    raise InsurerNotFound, 'insurer_not_found' if insurer_not_found?(response)
    raise Error, "http_#{response.code}" unless response.code == 200

    parsed = response.parsed_response
    raise Error, 'unexpected_payload' unless parsed.is_a?(Hash)

    parsed
  rescue HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, SocketError => e
    raise Error, e.class.name
  end

  # Corpo real observado: {"error":{"code":"insurer_not_found","message":"..."}}. Só o código é
  # lido — a mensagem repete o nome que o cliente digitou e não acrescenta nada ao agente.
  def insurer_not_found?(response)
    return false unless response.code == 404

    response.parsed_response.to_h.dig('error', 'code') == 'insurer_not_found'
  rescue StandardError
    false
  end

  def headers
    base = { 'Content-Type' => 'application/json', 'Accept' => 'application/json' }
    @token.present? ? base.merge('Authorization' => "Bearer #{@token}") : base
  end
end
