# Uma ferramenta LIGADA a um agente, pronta para o turno (#312).
#
# Existem duas origens — a HTTP cadastrada pelo dono da conta (`Autonomia::Agents::Tool`) e a
# nativa declarada em código (`Tools::Native::Base`). Quem executa o turno não deveria precisar
# saber qual é qual: aqui as duas viram o mesmo contrato — `slug`, `openai_schema`, `execute`.
#
# `execute` NUNCA levanta. Erro vira JSON curto e nomeado, que o modelo lê e trata. Um turno não
# pode morrer porque uma ferramenta falhou.
class Autonomia::Agents::Tools::Bound
  MAX_OUTPUT_CHARS = 8_000

  # Todas as ferramentas ligadas a este agente, na ordem: primeiro as cadastradas (por id),
  # depois as nativas (na ordem do catálogo).
  def self.for_agent(agent)
    records = agent.tools.enabled.order(:id).map { |record| new(record: record, agent: agent) }
    natives = Autonomia::Agents::Tools::Registry.for_agent(agent)
                                                .map { |klass| new(native: klass, agent: agent) }
    records + natives
  end

  def initialize(agent:, record: nil, native: nil)
    @agent = agent
    @record = record
    @native = native
  end

  def slug
    (@record&.slug || @native&.slug).to_s
  end

  def openai_schema
    (@record || @native).openai_schema
  end

  def native?
    @native.present?
  end

  # -> String para o modelo.
  def execute(call)
    args = JSON.parse(call['arguments'].presence || '{}')
    output = native? ? run_native(args) : run_http(args)
    output.to_s.truncate(MAX_OUTPUT_CHARS)
  rescue JSON::ParserError
    { error: 'invalid_tool_arguments' }.to_json
  end

  private

  def run_http(args)
    Autonomia::Agents::Tools::HttpExecutor.new(tool: @record, params: args).call
  rescue Autonomia::Agents::Tools::HttpExecutor::Error => e
    { error: http_error_code(e.message) }.to_json
  end

  # Defesa na FRONTEIRA com o modelo. Hoje a mensagem do executor é segura ("tool_http_error:
  # 404 Not Found" — só status e frase padrão do HTTP), mas repassá-la inteira é uma porta aberta:
  # basta alguém, um dia, incluir corpo de resposta ou URL na exceção para vazar sem ninguém notar.
  # Aqui só passa o que é útil ao modelo e comprovadamente inócuo: a CATEGORIA do erro e o status
  # numérico. Texto livre é descartado.
  def http_error_code(message)
    text = message.to_s
    kind = text.split(':').first.to_s.strip.presence || 'tool_http_error'
    kind = 'tool_http_error' unless kind.match?(/\A[a-z_]+\z/)
    status = text[/\b([1-5]\d{2})\b/, 1]
    status.present? ? "#{kind}: #{status}" : kind
  end

  # A nativa carrega credencial e assinatura; a mensagem da exceção pode conter requisição assinada.
  # Por isso o rescue é largo e a saída é um código, nunca `e.message`.
  def run_native(args)
    @native.new(agent: @agent, params: args).call
  rescue StandardError => e
    Rails.logger.warn("[autonomia][tool] native failed slug=#{slug} #{e.class}")
    { error: 'tool_execution_error' }.to_json
  end
end
