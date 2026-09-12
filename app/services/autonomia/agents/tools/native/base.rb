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

    # O fecho quando acabou o prazo e ALGO já tinha sido entregue. Não é a mensagem de falha: dizer
    # "não consegui" a quem acabou de receber preço é desmentir o que ele está lendo.
    # DE CLASSE, como `accepted_message` (lido pelo `Bound`) e `waiting_message`/`failure_message`
    # (publicados pelo job): o fecho sai mesmo quando o agente já não existe e não há instância. A ferramenta que o redefinir como
    # método de INSTÂNCIA está escrevendo uma frase que nunca sai — foi o caso da cotação até
    # 10/09/2026 (entrega 4), e `contrato_de_nivel_spec` reprova isso.
    def partial_message
      'Algumas consultas não responderam a tempo. O que chegou está aqui em cima.'
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

    # Texto que o CÓDIGO publica quando a execução acaba sem se saber se o trabalho foi feito
    # (entrega 5): o job decidiu submeter e o número nunca chegou — o processo morreu, ou o portal
    # ficou mudo. Não é a frase de falha: "não consegui" afirmaria o que não se sabe.
    def uncertain_message
      'Não consegui confirmar o resultado da consulta. Um atendente vai conferir e retomar daqui.'
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
    def openai_schema(agent = nil)
      {
        type: 'function',
        name: slug,
        description: description,
        parameters: objeto(params_for(agent)),
        strict: true
      }
    end

    # Os parâmetros DE UMA CONTA. O padrão é a lista fixa da classe.
    def params_for(_agent)
      params
    end

    # UM OBJETO EM STRICT MODE: todas as chaves em `required`, `additionalProperties: false`, e o
    # opcional dito pelo tipo (`[tipo, 'null']`). Recursivo: um parâmetro `object` carrega
    # `properties` (a mesma forma de lista), e é assim que o formulário de auto entra ANINHADO —
    # `vehicle.plate` é `vehicle: { plate }`, como o adapter lê, e não um campo plano com ponto.
    def objeto(lista)
      {
        type: 'object',
        properties: lista.to_h { |param| [param['name'], propriedade(param)] },
        required: lista.pluck('name'),
        additionalProperties: false
      }
    end

    def propriedade(param)
      base = case param['type']
             when 'object'
               objeto(Array(param['properties'])).merge(description: param['description']).compact
             when 'array'
               { 'type' => 'array', 'items' => { 'type' => param['items'] || 'string' },
                 'description' => param['description'] }.compact
             else
               param.slice('type', 'description')
             end
      return base unless param['required'] == false

      chave = base.key?(:type) ? :type : 'type'
      base.merge(chave => [base[chave], 'null'])
    end
  end

  # `delivery` é o contexto do turno (conversa), quando há um. A ferramenta continua sem saber de
  # conversa para TRABALHAR; ela só o carrega para o registro de recusa dizer qual conversa foi.
  #
  # `conversation` é a conversa SEM o turno (entrega 8): o `AsyncRunJob` monta a ferramenta para
  # `start`, `poll` e `closing_deliveries` fora do turno e, de propósito, sem `delivery` — a
  # presença dele é o que diz "estou dentro do turno, com o modelo esperando" (é por ela que
  # `InsuranceQuote::Veiculo#consultar_placa` escolhe a sessão). Uma ferramenta que trabalha sobre o
  # que a CONVERSA já tem (a proposta individual lê a última cotação dela) precisa da conversa nos
  # dois contextos, e é `#conversation` que a entrega: pelo `delivery` no turno, por aqui no job.
  #
  # `run` é a LINHA DA EXECUÇÃO (rodada 3 da entrega 8), e serve para uma coisa só: a ferramenta
  # perguntar o que JÁ FOI PUBLICADO. A identidade de uma entrega publicada é o
  # `ToolRun#delivery_token` — `execution_key` mais o digest do conteúdo —, e sem a linha não há
  # como montá-lo. É o que permite à proposta individual decidir o que falta entregar pela MENSAGEM
  # no banco, e não pelo handle (o handle avançava mesmo quando a publicação voltava `blocked`, e o
  # arquivo ficava contado como enviado sem existir; Codex, rodada 2, P2). nil no turno e nas
  # superfícies sem execução.
  def initialize(agent:, params: {}, delivery: nil, conversation: nil, run: nil)
    @agent = agent
    @params = params.to_h.deep_stringify_keys
    @delivery = delivery
    @conversation = conversation
    @run = run
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

  # O QUE A EXECUÇÃO GUARDA COMO ARGUMENTOS quando o aceite a abre (`Bound#accept_async`, rodada de
  # correção da entrega 8): o que o modelo escreveu e, se a ferramenta precisar FIXAR algo no
  # aceite, o que ela acrescenta. A proposta individual grava aqui a cotação de origem — escolhida
  # UMA vez, no turno, com o modelo e o cliente olhando para a mesma lista de preços — para `start`
  # e `poll` usarem só ela: escolher de novo no job, minutos depois, era como a proposta da cotação
  # A saía enquanto o cliente já corria a cotação B (Codex, P1). Lido pelo `AsyncRunJob` como
  # `params` nas passadas seguintes. -> Hash serializável. O padrão é o que o modelo escreveu.
  def argumentos
    params
  end

  # O QUE AINDA VALE ENTREGAR QUANDO A EXECUÇÃO ACABA SEM FECHAR. Em 08/09/2026 uma cotação
  # entregou cinco preços e morreu no prazo: o comparativo em PDF só era gerado no caminho feliz,
  # então não saiu — e `fail_run` não avisava nada porque já havia entrega. O cliente ficou com
  # preços soltos, sem comparativo e sem uma palavra.
  # -> Array de textos para o cliente. Vazio por padrão.
  def closing_deliveries(_handle)
    []
  end

  # O QUE VIROU MENSAGEM NO PRÓPRIO ENCERRAMENTO (rodada 5 da entrega 8). `closing_deliveries` monta o
  # que ainda vale entregar ANTES de a mensagem existir, e quem publica é o encerramento, logo depois
  # — não há passada seguinte, então o que sai ali ficava fora de qualquer registro que a ferramenta
  # faça PELA MENSAGEM publicada (a proposta individual anota na cotação o que virou proposta, e é o
  # que a medida da entrega 7 lê). O encerramento chama isto DEPOIS de publicar, e a pergunta que a
  # ferramenta faz continua sendo a mesma de sempre: existe a mensagem com o token? Nunca o handle.
  # -> nada. Padrão: nada.
  def confirmar_publicadas(_handle)
    nil
  end

  # ESTA ENTREGA AINDA PODE SER PUBLICADA? (rodada 3 da entrega 8, P1 do Codex.)
  #
  # A publicação nem sempre acontece logo depois do `poll`: ela é ADIADA enquanto a cadeia de
  # entrega humanizada do turno não drena (até 90 s, `AsyncPublishJob`) e pode ser RETOMADA depois.
  # Nesse intervalo o mundo muda, e há ferramenta cujo resultado deixa de valer — a proposta
  # individual sai de uma COTAÇÃO, e uma cotação refeita no meio torna o arquivo o do risco errado
  # com cara de certo. O publicador pergunta isto imediatamente antes de criar a mensagem, sob o
  # lock (`AutorizacaoDaExecucao`), e o `false` é recusa da mesma classe da execução morta:
  # registrada, sem mensagem ao cliente.
  #
  # Recebe a ENTREGA além da execução porque a mesma execução publica coisas de naturezas
  # diferentes: o arquivo que saiu do trabalho e as frases que EXPLICAM o que houve (a recusa
  # "a cotação foi refeita", o fecho do job). Barrar tudo deixaria o cliente em silêncio depois de
  # "já estou buscando" — que é o defeito oposto. -> true por padrão.
  def publicavel?(_run, _entrega)
    true
  end

  # A ENTREGA QUE UMA MENSAGEM JÁ PUBLICADA POR ESTA EXECUÇÃO CARREGA (rodada 4 da entrega 8, P1 do
  # Codex). A retomada de um envio pendente (`RetomadaDeEnvio`, e o varredor que a chama) não tem
  # entrega em mãos: tem a MENSAGEM, e dela o token (`ToolRun#delivery_token`, o digest do conteúdo).
  # Sem a entrega não há como fazer a pergunta acima, e o reenvio entregava ao cliente o arquivo de
  # uma cotação que já tinha sido refeita — existir no painel não é ter chegado ao cliente. Quem sabe
  # reconhecer o próprio conteúdo pelo token é a ferramenta.
  # -> a entrega, ou nil. O padrão é nil: quem não reconhece nada não barra nada.
  def entrega_do_token(_run, _token)
    nil
  end

  private

  attr_reader :agent, :params, :delivery, :run

  def account
    agent.account
  end

  # A conversa em que a ferramenta trabalha, no turno (via `delivery`) e no job (via a execução).
  # nil nas superfícies sem conversa (Testar, Copiloto, playground).
  def conversation
    @conversation || delivery.try(:conversation)
  end

  # Recusa nomeada da ferramenta SÍNCRONA, em JSON. Passa pelo registro (entrega 6) como as demais.
  def error(code)
    ::Autonomia::Agents::Tools::Recusa.para_modelo(code, slug: self.class.slug, delivery: delivery, agente: agent)
  end

  # Recusa em PROSA: registra, com os NOMES dos parâmetros que faltaram e ONDE aconteceu, e devolve o
  # texto, que não muda. `turno` é a ferramenta síncrona pedindo um dado antes de trabalhar; `envio`
  # é a assíncrona recusando na entrega (a proposta individual, quando a cotação de origem morreu
  # entre o `start` e o `poll`). A conversa vem de `#conversation` — pelo `delivery` no turno, pela
  # execução no job —, e é por isso que a recusa do job sai com a conversa, e não com `-`.
  def recusar(codigo, texto, faltando: [], onde: 'turno')
    ::Autonomia::Agents::Tools::Recusa.registrar(codigo, slug: self.class.slug, agente: agent, faltando: faltando, onde: onde,
                                                         conversa: conversation&.id)
    texto
  end
end
