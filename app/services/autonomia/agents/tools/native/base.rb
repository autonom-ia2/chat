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

    # ASSÍNCRONA (#313). Falso por padrão. A ferramenta que declara verdadeiro NÃO roda dentro do
    # turno: ela é ACEITA, o turno responde na hora ("já estou consultando"), e o resultado chega
    # depois, numa mensagem própria.
    #
    # É o que destrava a cotação, que leva até ~90s: o turno inteiro tem 120s de teto de HTTP
    # (`ResponsesClient#create_with_tool_executor`) e o Sidekiq derruba worker parado no shutdown
    # (`:timeout: 25`). Esperar dentro do turno perderia as duas pontas.
    #
    # Uma ferramenta assíncrona NÃO implementa `#call`; implementa `#start` e `#poll`:
    #
    #   #start                        -> Hash serializável (o "handle": ex. o id da cotação no
    #                                    portal). Precisa VOLTAR RÁPIDO — submete, não espera.
    #   #poll(handle:, attempt:)      -> Tools::Progress. Uma checagem barata. Pode devolver
    #                                    entregas parciais em qualquer consulta.
    #
    # Duas fases em vez de um `#call` de 90 segundos porque o worker não pode ficar preso: um deploy
    # no meio mata o job e o Sidekiq o reexecuta do zero — o que aqui significa COTAR DE NOVO na
    # seguradora. É o mesmo desenho de `EmailCampaigns::Ai::PollJob`, que já roda em produção.
    def async?
      false
    end

    # O que o modelo lê ao aceitar o disparo. Curto e sem promessa de prazo — ele usa isto para
    # avisar o cliente na MESMA resposta (a rodada de ferramentas é única: a segunda chamada ao
    # modelo já vai sem `tools`, então não há segunda chance de falar).
    def accepted_message
      'Consulta iniciada. Avise o cliente que você está buscando e que volta com o resultado ' \
        'nesta conversa em instantes. Não invente valores nem prazos.'
    end

    # Texto que o CÓDIGO publica quando o turno não avisou o cliente (o modelo ficou em silêncio,
    # a IA falhou, a porta de engajamento fechou). O aviso não pode depender de o modelo lembrar.
    def waiting_message
      'Estou consultando agora. Assim que tiver o resultado, mando aqui.'
    end

    # Texto que o CÓDIGO publica quando a execução falha ou estoura o prazo. É escrito por nós, e
    # não pela ferramenta, de propósito: a mensagem de uma exceção pode carregar requisição assinada
    # ou texto vindo do portal, e isso não pode chegar ao cliente.
    def failure_message
      'Não consegui concluir a consulta agora. Um atendente vai retomar daqui.'
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
  # Só ferramenta SÍNCRONA implementa. A assíncrona implementa `#start` e `#poll`.
  def call
    raise NotImplementedError, "#{self.class} must implement #call"
  end

  # ASSÍNCRONA — submete o trabalho e devolve o handle (Hash serializável) para as consultas
  # seguintes. Roda dentro de um job, não do turno; PODE levantar (o job trata e registra a falha).
  def start
    raise NotImplementedError, "#{self.class} must implement #start"
  end

  # ASSÍNCRONA — UMA consulta. `attempt` é base zero e serve para a ferramenta decidir quando parar
  # de esperar uma seguradora específica (prazo por seguradora, não só teto global). -> Tools::Progress.
  def poll(handle:, attempt:)
    raise NotImplementedError, "#{self.class} must implement #poll"
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
