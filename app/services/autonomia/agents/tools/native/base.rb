# Contrato de uma ferramenta NATIVA de agente (#312).
#
# A ferramenta HTTP (`Autonomia::Agents::Tool` + `Tools::HttpExecutor`) resolve o caso genérico:
# o dono da conta cadastra uma URL e um template. Ela NÃO resolve o caso em que a chamada precisa
# de código nosso — assinatura de requisição, credencial no cofre, validação de entrada, erro
# tipado. É esse buraco que a ferramenta nativa fecha.
#
# Nativa é declarada em CÓDIGO (uma classe por ferramenta, registrada no Registry) e ligada por
# conta através de `agent.config['native_tool_slugs']`. O dono da conta escolhe quais ligar; nunca
# escreve a URL nem o cabeçalho — é isso que permite falar com o nosso adapter sem expor como.
class Autonomia::Agents::Tools::Native::Base
  # Toda ferramenta nativa devolve STRING para o modelo, igual à HTTP. Erro também é string: o
  # modelo lê e decide o que fazer, em vez de o turno morrer.
  MAX_OUTPUT_CHARS = 8_000

  class << self
    # Identificador estável. Vira o nome da função no prompt, então segue o mesmo formato da
    # ferramenta HTTP (letras, dígitos e sublinhado; começa por letra).
    def slug
      raise NotImplementedError, "#{self} must implement .slug"
    end

    def tool_name
      slug.humanize
    end

    # O que o modelo lê para decidir usar. Específico, nunca genérico.
    def description
      raise NotImplementedError, "#{self} must implement .description"
    end

    # Mesmo formato de `Autonomia::Agents::Tool#param_schema`, para o schema sair idêntico:
    # [{ 'name' =>, 'type' =>, 'description' =>, 'required' => }]
    def params
      []
    end

    # Gate por agente: uma ferramenta que depende de recurso não configurado (conexão ausente,
    # feature desligada) não deve nem aparecer no prompt. Melhor não oferecer do que oferecer e
    # falhar na frente do cliente.
    def available_for?(_agent)
      true
    end

    def openai_schema
      {
        type: 'function',
        name: slug,
        description: description,
        parameters: {
          type: 'object',
          properties: params.to_h { |param| [param['name'], param.slice('type', 'description')] },
          required: params.reject { |param| param['required'] == false }.pluck('name'),
          additionalProperties: false
        },
        strict: true
      }
    end
  end

  def initialize(agent:, params: {})
    @agent = agent
    @params = params.to_h.deep_stringify_keys
  end

  # -> String. NUNCA levanta: quem chama é o executor de ferramentas do turno.
  def call
    raise NotImplementedError, "#{self.class} must implement #call"
  end

  private

  attr_reader :agent, :params

  def account
    agent.account
  end

  def error(code)
    { error: code }.to_json
  end
end
