# Contrato de uma ferramenta NATIVA de agente (#312).
#
# A ferramenta HTTP (`Autonomia::Agents::Tool` + `Tools::HttpExecutor`) resolve o caso genérico:
# o dono da conta cadastra uma URL e um template. Ela NÃO resolve o caso em que a chamada precisa
# de código nosso — assinatura de requisição, credencial no cofre, validação de entrada, erro
# tipado. É esse buraco que a ferramenta nativa fecha.
#
# Nativa é declarada em CÓDIGO (uma classe por ferramenta, registrada no Registry) e ligada por
# agente através de `agent.config['native_tool_slugs']`, menos no Agente de Cotação, cuja lista é a do
# deploy (`Agent#ferramentas_nativas`, fatia 2 do #420). Nunca se escreve a URL nem o cabeçalho — é isso
# que permite falar com o nosso adapter sem expor como.
class Autonomia::Agents::Tools::Native::Base
  # Toda ferramenta nativa devolve STRING para o modelo, igual à HTTP. Erro também é string: o
  # modelo lê e decide o que fazer, em vez de o turno morrer.
  MAX_OUTPUT_CHARS = 8_000

  # DOIS PARÂMETROS COM O MESMO NOME NO MESMO OBJETO. `objeto` monta `properties` por `to_h` — o
  # segundo apaga o primeiro em silêncio — e `required` por `pluck`, que fica com os dois: um
  # `required` de N+1 entradas para N propriedades, que a OpenAI responde com HTTP 400 na chamada
  # INTEIRA (`has non-unique elements`), e o agente fica MUDO. É a mesma classe de falha de
  # 08/09/2026, e ela é alcançável sem ninguém editar este repositório: os parâmetros de auto nascem
  # do `quote/schema` do adapter, e um campo de RAIZ novo lá com o nome de um grupo ou do nó das
  # frases bastaria. Por isso a guarda é aqui, na MONTAGEM, e não numa spec: spec não roda em
  # produção no dia em que o adapter muda.
  NomeDeParametroDuplicado = Class.new(StandardError)

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

    # OS FATOS DE UM EVENTO DESTA EXECUÇÃO, para o MODELO (PR C, `Tools::Evento`). Nenhuma frase ao cliente sai
    # daqui: o motor dispara o evento, e a Lia fala num turno de modelo, com a voz dela, a partir da descrição do
    # tipo e destes fatos. DE CLASSE, e a partir da LINHA (`run`): o evento de falha sai mesmo quando o agente já
    # não existe e não há instância. -> texto para o modelo, ou nil (a descrição do tipo basta). Nunca dado
    # pessoal achado por busca de documento.
    def fatos_do_evento(_tipo, _run)
      nil
    end

    # O HANDLE DESTA EXECUÇÃO TEM RESULTADO GUARDADO? (fatia 2 do #420.) Lido por
    # `ToolRun#resultado_obtido?` para contar a execução como pedido feito. De classe: quem pergunta tem a
    # linha, não a ferramenta montada. -> false por padrão.
    def resultado_guardado?(_handle)
      false
    end

    # EM `strict: true` NÃO EXISTE CAMPO FORA DE `required`.
    #
    # A OpenAI recusa a chamada INTEIRA — não a ferramenta, a chamada — quando `required` não lista
    # todas as chaves de `properties`. Medido em produção em 08/09/2026, com a Lia muda numa conversa
    # de WhatsApp real: `Invalid schema for function 'consultar_condicoes_gerais': 'required' is
    # required to be supplied and to be an array including every key in properties. Missing 'ramo'`.
    # Uma ferramenta com um parâmetro opcional derrubava o turno todo, e o agente não respondia nada.
    #
    # O jeito de dizer "opcional" em strict mode é OUTRO: o campo entra em `required` e o tipo dele
    # passa a aceitar `null`. O modelo então manda `null` quando não tem o valor, em vez de omitir a
    # chave — e a ferramenta recebe nil, que é o que ela já esperava de um parâmetro ausente.
    # `agent` é opcional: a ferramenta que monta o formulário a partir do que a CONTA conectou
    # (entrega 2 do Agente de Cotação — os ~90 campos de auto vêm do adapter) precisa saber de quem é
    # o formulário. As demais ignoram, e `params_for` cai na lista fixa da classe.
    # `especialista` também: quem monta o turno de um especialista (`Specialist#tools`) diz qual é, e
    # a cotação usa isso para dar a cada especialista o formulário do ramo dele (chat#591).
    #
    # A DESCRIÇÃO SAI DOS PARÂMETROS QUE VÃO AO MODELO (revisão da chat#592): as duas coisas que ele lê sobre a
    # ferramenta não podem se contradizer, e a regra mais perto da ação vence. Montadas uma da outra, não há como.
    def openai_schema(agent = nil, especialista: nil)
      parametros = params_for(agent, especialista: especialista)
      {
        type: 'function',
        name: slug,
        description: description_for(parametros),
        parameters: objeto(parametros),
        strict: true
      }
    end

    # Os parâmetros DE UMA CONTA (e de um especialista). O padrão é a lista fixa da classe.
    def params_for(_agent, **)
      params
    end

    # A descrição para ESTES parâmetros. O padrão é a fixa da classe.
    def description_for(_parametros)
      description
    end

    # UM OBJETO EM STRICT MODE: todas as chaves em `required`, `additionalProperties: false`, e o
    # opcional dito pelo tipo (`[tipo, 'null']`). Recursivo: um parâmetro `object` carrega
    # `properties` (a mesma forma de lista), e é assim que o formulário de auto entra ANINHADO —
    # `vehicle.plate` é `vehicle: { plate }`, como o adapter lê, e não um campo plano com ponto.
    def objeto(lista)
      conferir_nomes!(lista)
      {
        type: 'object',
        properties: lista.to_h { |param| [param['name'], propriedade(param)] },
        required: lista.pluck('name'),
        additionalProperties: false
      }
    end

    # Levanta com os nomes repetidos — nunca com o valor de nada. Ver `NomeDeParametroDuplicado`.
    def conferir_nomes!(lista)
      nomes = lista.pluck('name')
      repetidos = nomes.tally.select { |_, vezes| vezes > 1 }.keys
      return if repetidos.empty?

      raise NomeDeParametroDuplicado, "#{slug}: #{repetidos.join(', ')}"
    end

    def propriedade(param)
      base = case param['type']
             when 'object'
               objeto(Array(param['properties'])).merge(description: param['description']).compact
             when 'array'
               { 'type' => 'array', 'items' => { 'type' => param['items'] || 'string' },
                 'description' => param['description'] }.compact
             else
               param.slice('type', 'description', 'enum')
             end
      return base unless param['required'] == false

      chave = base.key?(:type) ? :type : 'type'
      anulavel = base.merge(chave => [base[chave], 'null'])
      # O `enum` restringe o valor por conta própria: sem `null` na lista, o `null` que o tipo aceita
      # seria recusado pelo próprio `enum`, e o opcional deixaria de ser opcional (chat#591).
      anulavel['enum'] ? anulavel.merge('enum' => anulavel['enum'] + [nil]) : anulavel
    end
  end

  # `delivery` é o contexto do turno (conversa), quando há um. A ferramenta continua sem saber de
  # conversa para TRABALHAR; ela só o carrega para o registro de recusa dizer qual conversa foi.
  #
  # `run` é a LINHA DA EXECUÇÃO (entrega 8a), e serve para uma coisa só: a ferramenta saber o que o
  # publicador ACEITOU entregar. A identidade de uma entrega é o `ToolRun#delivery_token` —
  # `execution_key` mais o digest do conteúdo —, e sem a linha não há como montá-la; o aceite
  # também mora nela (`Tools::EntregaAceita`). Nunca pelo handle da ferramenta, que só conhece o
  # que se EMITIU.
  #
  # O `AsyncRunJob` monta a ferramenta para `start`, `poll` e `closing_deliveries` fora do turno e,
  # de propósito, SEM `delivery` — a presença dele é o que diz "estou dentro do turno, com o modelo
  # esperando" (é por ela que `InsuranceQuote::Veiculo#consultar_placa` escolhe a sessão).
  #
  # PADRÃO `nil`, e quem o lê hoje é a COTAÇÃO (`InsuranceQuote::Fecho`). Quem não o usa não muda de
  # comportamento — nenhuma nativa sobrescreve `initialize`, e `base_contrato_de_nivel_spec`
  # percorre o catálogo inteiro para provar isso.
  # `operador` é QUEM está pedindo, quando a ferramenta age em nome de uma
  # pessoa e não do agente (#568, Guia da Plataforma). Nulo nas demais: o
  # atendimento fala com o cliente, que não tem permissão dentro da conta.
  def initialize(agent:, params: {}, delivery: nil, run: nil, operador: nil)
    @agent = agent
    @params = params.to_h.deep_stringify_keys
    @delivery = delivery
    @run = run
    @operador = operador
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

  # OS DOIS ABAIXO SÃO DE INSTÂNCIA, e isso não é detalhe: o `Bound` chama `precheck` e o
  # `AsyncRunJob` chama `closing_deliveries` numa instância (a ferramenta precisa da conexão e dos
  # parâmetros para conferir e para gerar o comparativo). Até 10/09/2026 os defaults viviam em
  # `class << self` — nível que ninguém chamava; uma ferramenta assíncrona sem a versão de instância
  # (não havia nenhuma) teria levantado `NoMethodError`, engolido pelo `rescue` do chamador.
  # `base_contrato_de_nivel_spec` guarda o nível de cada método deste contrato; foi o mesmo defeito,
  # ao contrário, que fez a frase de encerramento parcial da cotação nunca rodar (entrega 4).
  # CONFERÊNCIA ANTES DE ACEITAR, e ela existe porque O MODELO ESPERA O RETORNO DA FERRAMENTA:
  # `ResponsesClient#create_with_tool_executor` alimenta a segunda chamada com a saída de cada
  # função. O canal de volta ao modelo não falta — a assíncrona é que o preenchia com uma frase
  # fixa e adiava o trabalho, então o modelo anunciava sucesso e só depois descobria a recusa.
  #
  # Quem consegue saber, ainda no turno, que o pedido não vai dar em nada, responde aqui: o texto
  # volta pelo canal que o modelo já lê, e NENHUMA execução é aberta.
  #
  # -> String (o que o modelo recebe no lugar do aceite), `Native::Conferencia` (o mesmo texto
  # mais o motivo e os NOMES dos campos que faltaram, para o registro de recusa da entrega 6) ou
  # nil (segue o fluxo normal).
  # NUNCA levanta e nunca bloqueia: conferência indisponível deixa o pedido seguir.
  def precheck
    nil
  end

  # A IDENTIDADE DO PEDIDO (entrega 10): o digest da entrada NORMALIZADA — pelo adapter, não por
  # nós — que diz se dois pedidos são o mesmo pedido. O `Bound` a compara com a última execução da
  # conversa antes de abrir outra: "e aí, saiu?" com os mesmos dados não abre cotação nova.
  # -> String curta, ou nil quando não há como saber (conferência indisponível): nil nunca barra.
  def pedido
    nil
  end

  # O QUE AINDA VALE ENTREGAR QUANDO A EXECUÇÃO ACABA SEM FECHAR. Em 08/09/2026 uma cotação
  # entregou cinco preços e morreu no prazo: o comparativo em PDF só era gerado no caminho feliz,
  # então não saiu — e `fail_run` não avisava nada porque já havia entrega. O cliente ficou com
  # preços soltos, sem comparativo e sem uma palavra.
  #
  # `trabalho_novo` DIZ SE ESTA PASSADA PODE INICIAR TRABALHO NOVO no portal para produzir a entrega
  # (entrega 8). Verdadeiro no motor; FALSO no varredor, que varre até 500 linhas
  # em sequência dentro de um cron enquanto o Sidekiq desta instalação dá 25 s de shutdown — morto no
  # meio, a passada morre no meio do lote. Quem precisa de uma chamada nova devolve [] ali, e o
  # fecho reflete o que o cliente realmente tem. O que JÁ está pronto — um arquivo que a ferramenta
  # guardou no handle — sai pelos dois caminhos; a cotação não tem nada assim (o comparativo só
  # existe depois de uma chamada ao portal), então pelo varredor ela entrega [] e só fecha.
  # -> Array de entregas de ARQUIVO. Vazio por padrão.
  def closing_deliveries(_handle, trabalho_novo: true) # rubocop:disable Lint/UnusedMethodArgument
    []
  end

  # O CLIENTE JÁ TEM RESULTADO DESTA EXECUÇÃO? (entrega 8.)
  #
  # `ToolRun#delivered_count` não responde isso: ele conta QUALQUER item aceito para publicação,
  # inclusive as entregas legadas de antes da PR C. Quem sabe distinguir resultado de recado é a ferramenta,
  # não o motor — e é por esta pergunta que o encerramento escolhe o evento de desfecho.
  #
  # A RESPOSTA É SOBRE O ACEITE, NÃO SOBRE A EMISSÃO: o handle da ferramenta só sabe o que ela
  # tentou entregar, e avança mesmo quando a publicação é recusada. É para esta pergunta que a
  # ferramenta recebe `run:` — com ela monta a identidade de cada entrega que emite e pergunta à
  # lista do aceite (`Tools::EntregaAceita`), onde a publicação aceita, imediata ou ADIADA, está
  # registrada. Pela mensagem não serve: a adiada ainda não é uma.
  # -> false por padrão: quem não sabe responder não afirma que entregou.
  def resultado_entregue?(_handle)
    false
  end

  # O RESULTADO EXISTE E NÃO CHEGOU AO CLIENTE? (fatia 3 do #420.) Verdade quando a ferramenta guardou
  # resultado e nenhuma entrega dele foi aceita: o desfecho é `valores_guardados`, e a Lia diz que ele pode
  # pedir aqui mesmo. -> false por padrão.
  def resultado_a_pedir?(_handle)
    false
  end

  # E SOBROU ALGO POR ENTREGAR? (entrega 8.) Perguntado DEPOIS das entregas do
  # encerramento: o desfecho por prazo diz que algo ficou pelo caminho, e dizê-lo a quem recebeu tudo o
  # que pediu é mentir.
  # -> false por padrão: sem sobra conhecida, o desfecho é `concluida`.
  def resta_entregar?(_handle)
    false
  end

  private

  attr_reader :agent, :params, :delivery, :run

  def account
    agent.account
  end

  # Recusa nomeada da ferramenta SÍNCRONA, em JSON. Passa pelo registro (entrega 6) como as demais.
  def error(code)
    ::Autonomia::Agents::Tools::Recusa.para_modelo(code, slug: self.class.slug, delivery: delivery, agente: agent)
  end

  # Recusa em PROSA da ferramenta síncrona (ela pediu um dado antes de trabalhar): registra, com os
  # NOMES dos parâmetros que faltaram, e devolve o texto, que não muda.
  def recusar(codigo, texto, faltando: [])
    ::Autonomia::Agents::Tools::Recusa.registrar(codigo, slug: self.class.slug, agente: agent, faltando: faltando,
                                                         conversa: ::Autonomia::Agents::Tools::Recusa.conversa_de(delivery))
    texto
  end
end
