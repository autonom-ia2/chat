# A pergunta do Decisor (#858) ao Jev: uma `choice` com as respostas do Decisor como critérios.
#
# Mesmo molde de `TypesafeAi::ImportSchemaResolver`: a resposta do provedor é conferida inteira
# (modelo, tipo, certeza entre 0 e 1 e escolha entre as chaves do Decisor) antes de valer.
#
# O custo do Jev é NOSSO (decisão do Rodrigo, 03/10/2026) e fica em `Crm::AiUsageEvent` com a
# feature `decisor` (`jev_guia` quando é o Guia classificando, `Decisores::Classificacao`). O Jev
# devolve `usage` com `input_tokens`/`output_tokens`; o preço por token está em `Crm::Ai::Pricing`.
class TypesafeAi::Decisor
  class Error < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code)
    end
  end

  FEATURE = 'decisor'.freeze
  PERGUNTA = 'decisao'.freeze
  Resultado = Struct.new(:resposta, :certeza, :modelo, keyword_init: true)

  def initialize(client: TypesafeAi::Client.new, model: TypesafeAi::Config.model, feature: FEATURE)
    @client = client
    @model = model
    @feature = feature
  end

  def decidir(decisor:, estado:)
    comeco = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response = @client.evaluate(model: @model, state: estado.para_o_jev(decisor), questions: perguntas(decisor))
    registrar_custo(decisor.account, response, comeco)
    resultado(decisor, response)
  rescue KeyError, TypeError, NoMethodError
    raise Error, 'typesafe_invalid_response'
  rescue TypesafeAi::Client::Error => e
    raise Error, e.code
  end

  private

  def perguntas(decisor)
    criterios = Array(decisor.respostas).to_h { |resposta| [resposta['chave'], resposta['descricao']] }
    { PERGUNTA => { type: 'choice', instructions: decisor.pergunta, criteria: criterios } }
  end

  def resultado(decisor, response)
    resposta = response.fetch('answers').fetch(PERGUNTA)
    certeza = resposta.fetch('confidence')
    escolha = resposta.fetch('choice')
    valido = response.fetch('model') == @model && resposta.fetch('type') == 'choice' &&
             certeza.is_a?(Numeric) && certeza.finite? && certeza.between?(0, 1) && decisor.resposta?(escolha)
    raise Error, 'typesafe_invalid_response' unless valido

    Resultado.new(resposta: escolha, certeza: certeza.to_f, modelo: response.fetch('model'))
  end

  def registrar_custo(account, response, comeco)
    Crm::Ai::UsageRecorder.record(
      account: account, feature: @feature, model: response['model'].presence || @model, usage: response['usage'],
      latency_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - comeco) * 1000).round
    )
  end
end
