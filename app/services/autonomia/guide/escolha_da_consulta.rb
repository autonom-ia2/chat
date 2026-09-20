# Qual recurso da plataforma responde a esta pergunta (issue #533, 2ª volta).
#
# A primeira versão exigia um marcador escondido no fluxo do manual, e o Guia só
# consultava a conta quando o buscador trazia o fluxo marcado. Resultado: ele
# entendia a pergunta e mesmo assim não ia buscar o dado — foi o que fez
# "quantas caixas eu tenho" falhar em produção.
#
# Agora quem escolhe é quem entendeu a pergunta. O modelo recebe o catálogo
# derivado do roteador e devolve UM recurso dele, ou nada. A superfície continua
# fechada: o que ele devolver fora do catálogo é descartado aqui, e a leitura em
# si ainda passa pela permissão de quem perguntou.
class Autonomia::Guide::EscolhaDaConsulta
  INSTRUCAO = <<~TEXTO.freeze
    Você recebe a pergunta de quem opera uma plataforma de atendimento e a lista de
    recursos de leitura disponíveis na API dela.

    Escolha O ÚNICO recurso que responde à pergunta, exatamente como escrito na lista.
    Se a pergunta for sobre COMO fazer algo, sobre uma tela, ou se nenhum recurso
    responder, devolva nulo. Nunca invente um recurso fora da lista.
  TEXTO

  ESQUEMA = {
    type: 'object',
    properties: {
      recurso: { type: %w[string null], description: 'Recurso exatamente como na lista, ou nulo.' }
    },
    required: ['recurso'],
    additionalProperties: false
  }.freeze

  def initialize(account:, catalogo:)
    @account = account
    @catalogo = catalogo
  end

  # Devolve o nome do recurso, ou nil. Best-effort: qualquer falha vira nil, e o
  # Guia responde pelo manual como sempre fez.
  def para(pergunta)
    return nil if pergunta.to_s.strip.blank? || @catalogo.blank?

    credencial = ::Crm::Ai::CredentialResolver.new(account: @account).resolve
    return nil if credencial.blank?

    resposta = cliente(credencial).create(
      model: modelo, instructions: INSTRUCAO, input: entrada(pergunta),
      schema: ESQUEMA, reasoning_effort: 'low', timeout: 12
    )

    escolhido = extrair(resposta)
    @catalogo.include?(escolhido) ? escolhido : nil
  rescue StandardError => e
    Rails.logger.warn("[autonomia][guide][escolha] account=#{@account&.id} #{e.class}: #{e.message}")
    nil
  end

  private

  def cliente(credencial)
    ::Crm::Ai::ResponsesClient.new(credential: credencial, feature: 'guide_consulta', account: @account)
  end

  def modelo
    ::Crm::Ai::Config.respond_to?(:default_model) ? ::Crm::Ai::Config.default_model : 'gpt-4.1-mini'
  end

  def entrada(pergunta)
    "Pergunta: #{pergunta}\n\nRecursos disponíveis:\n#{@catalogo.join("\n")}"
  end

  def extrair(resposta)
    bruto = resposta.is_a?(Hash) ? (resposta[:text] || resposta['text']) : resposta.to_s
    dados = JSON.parse(bruto.to_s)
    dados['recurso'].presence
  rescue JSON::ParserError
    nil
  end
end
