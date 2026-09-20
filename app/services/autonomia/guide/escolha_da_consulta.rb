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

    Recurso com `:id` (como 'contacts/:id') lê UM item e exige o identificador em
    `parametros`. Só escolha um desses quando o identificador tiver sido informado
    pela pessoa ou tiver aparecido na conversa. Sem o identificador, prefira a rota
    de lista, ou devolva nulo.
  TEXTO

  # O cliente espera { name:, schema: } e manda `strict: true` para a OpenAI. No
  # modo estrito toda propriedade entra em `required`, todo objeto fecha com
  # `additionalProperties: false`, e não existe objeto de chave livre — por isso
  # os parâmetros vêm como lista de pares, não como mapa.
  ESQUEMA = {
    name: 'guia_consulta',
    schema: {
      type: 'object',
      properties: {
        recurso: { type: %w[string null], description: 'Recurso exatamente como na lista, ou nulo.' },
        parametros: {
          type: %w[array null],
          description: 'Um item por parâmetro da rota. Ex.: chave "id", valor "42".',
          items: {
            type: 'object',
            properties: { chave: { type: 'string' }, valor: { type: 'string' } },
            required: %w[chave valor],
            additionalProperties: false
          }
        }
      },
      required: %w[recurso parametros],
      additionalProperties: false
    }
  }.freeze

  def initialize(account:, catalogo:)
    @account = account
    @catalogo = catalogo
  end

  # Devolve { recurso:, parametros: }, ou nil. Best-effort: qualquer falha vira
  # nil, e o Guia responde pelo manual como sempre fez.
  def para(pergunta)
    return nil if pergunta.to_s.strip.blank? || @catalogo.blank?

    credencial = ::Crm::Ai::CredentialResolver.new(account: @account).resolve
    return nil if credencial.blank?

    resposta = cliente(credencial).create(
      model: modelo, instructions: INSTRUCAO, input: entrada(pergunta),
      schema: ESQUEMA, reasoning_effort: 'low', timeout: 12
    )

    extrair(resposta)
  rescue StandardError => e
    Rails.logger.warn("[autonomia][guide][escolha] account=#{@account&.id} #{e.class}: #{e.message}")
    nil
  end

  private

  def cliente(credencial)
    ::Crm::Ai::ResponsesClient.new(credential: credencial, feature: 'guide_consulta', account: @account)
  end

  # O mesmo modelo que o CRM usa para classificar. Antes isto perguntava por um
  # `default_model` que NUNCA existiu, então caía sempre no fallback gpt-4.1-mini
  # — um modelo que recusa o `reasoning.effort` que este cliente sempre envia.
  def modelo
    ::Crm::Ai::Config::MODEL_CLASSIFY
  end

  def entrada(pergunta)
    "Pergunta: #{pergunta}\n\nRecursos disponíveis:\n#{@catalogo.join("\n")}"
  end

  # A superfície é fechada aqui: recurso fora do catálogo é descartado.
  def extrair(resposta)
    bruto = resposta.is_a?(Hash) ? (resposta[:text] || resposta['text']) : resposta.to_s
    dados = JSON.parse(bruto.to_s)
    recurso = dados['recurso'].presence
    return nil unless @catalogo.include?(recurso)

    { recurso: recurso, parametros: pares_para_mapa(dados['parametros']) }
  rescue JSON::ParserError
    nil
  end

  # A lista de pares que o modo estrito exige vira o mapa que a Consulta usa.
  def pares_para_mapa(pares)
    return {} unless pares.is_a?(Array)

    pares.each_with_object({}) do |par, mapa|
      next unless par.is_a?(Hash)

      chave = par['chave'].to_s
      mapa[chave] = par['valor'] if chave.present?
    end
  end
end
