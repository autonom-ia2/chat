# Uma ferramenta LIGADA a um agente, pronta para o turno (#312).
#
# Existem duas origens — a HTTP cadastrada pelo dono da conta (`Autonomia::Agents::Tool`) e a
# nativa declarada em código (`Tools::Native::Base`). Quem executa o turno não deveria precisar
# saber qual é qual: aqui as duas viram o mesmo contrato — `slug`, `openai_schema`, `execute`.
#
# `execute` NUNCA levanta. Erro vira JSON curto e nomeado, que o modelo lê e trata. Um turno não
# pode morrer porque uma ferramenta falhou.
class Autonomia::Agents::Tools::Bound
  AsyncConfig = ::Autonomia::Agents::Tools::AsyncConfig

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

  # A ferramenta é assíncrona? Só nativa pode ser: a HTTP cadastrada pelo dono da conta não tem como
  # declarar o contrato start/poll.
  def async?
    native? && @native.async?
  end

  # -> String para o modelo.
  #
  # `delivery` é o contexto do turno de atendimento (conversa + vínculo do agente). Vem por CHAMADA
  # e não pela construção, para funcionar igual no caminho do principal e no do especialista.
  def execute(call, delivery: nil)
    args = JSON.parse(call['arguments'].presence || '{}')
    output = if async?
               accept_async(args, delivery)
             else
               native? ? run_native(args, delivery) : run_http(args, delivery)
             end
    output.to_s.truncate(MAX_OUTPUT_CHARS)
  rescue JSON::ParserError
    recusar('invalid_tool_arguments', delivery)
  end

  private

  # ASSÍNCRONA: não executa nada aqui. Registra a execução como `pending` e devolve ao modelo uma
  # confirmação curta, para ele avisar o cliente na MESMA resposta — a rodada de ferramentas é única
  # (`ResponsesClient#create_with_tool_executor` faz a segunda chamada sem `tools`).
  #
  # Fica em `pending` de propósito: quem promove para `running` e enfileira é o Responder, DEPOIS de
  # a entrega do turno começar. Se o turno morrer (a segunda chamada ao modelo estoura, ou a
  # instrução emite o sinal de silêncio), a execução é descartada e o portal nunca é chamado — em vez
  # de o cliente receber uma cotação do nada, sem nunca ter ouvido "vou cotar".
  def accept_async(args, delivery)
    refusal = async_refusal(delivery)
    return recusar(refusal, delivery) if refusal

    ferramenta = @native.new(agent: @agent, params: args, delivery: delivery)
    antecipado = precheck_native(ferramenta)
    return recusar_pela_conferencia(antecipado, delivery) if antecipado

    run, repetida = abrir(args, pedido_native(ferramenta), delivery)
    return recusar_pela_repeticao(repetida, delivery) if repetida
    return recusar('execucao_ja_em_andamento', delivery) if run.blank?

    delivery.register(run)
    @native.accepted_message
  rescue StandardError => e
    Rails.logger.warn("[autonomia][tool] async accept failed slug=#{slug} #{e.class}")
    recusar('tool_execution_error', delivery)
  end

  # TODA RECUSA EM JSON DESTE ARQUIVO PASSA POR AQUI (entrega 6; a da conferência, que é texto,
  # passa logo abaixo), e daqui vai para `Tools::Recusa`, que registra — qual
  # conversa, qual agente, o motivo e o que faltava — e monta o JSON que o modelo lê. Não existe outro
  # `{ error: ... }` neste arquivo: `recusa_guarda_spec` reprova quem escrever um. Antes, o agente
  # recusava e não deixava rastro nenhum; em 08/09/2026 uma cotação não abriu e ninguém soube por quê.
  def recusar(codigo, delivery, detalhe: nil)
    ::Autonomia::Agents::Tools::Recusa.para_modelo(codigo, slug: slug, delivery: delivery,
                                                           agente: @agent, detalhe: detalhe)
  end

  # A recusa da conferência tem forma própria: o modelo recebe TEXTO (o que perguntar ao cliente),
  # não JSON. A ferramenta pode devolver só a frase (String) ou uma `Native::Conferencia`, com o
  # motivo e a lista do que faltou — é essa lista que o registro leva. Sem ela, "faltam dados" no
  # registro não diria QUAIS, e quais é o que se quer saber.
  def recusar_pela_conferencia(conferencia, delivery)
    ::Autonomia::Agents::Tools::Recusa.registrar(
      conferencia.try(:motivo) || 'conferencia_recusou', slug: slug, agente: @agent, faltando: conferencia.try(:faltando),
                                                         conversa: ::Autonomia::Agents::Tools::Recusa.conversa_de(delivery)
    )
    conferencia.to_s
  end

  # Compara com a última consulta e abre, na mesma seção crítica (entrega 10): -> [run, repetida].
  def abrir(args, pedido, delivery)
    ::Autonomia::Agents::ToolRun.abrir_ou_repetida(
      agent: @agent, slug: slug, arguments: args, pedido: pedido,
      scope: { conversation_id: delivery.conversation.id, agent_inbox_id: delivery.agent_inbox&.id,
               origin_message_id: delivery.origin_message_id }
    )
  end

  # "E AÍ, SAIU?" NÃO ABRE COTAÇÃO NOVA (entrega 10). O pedido tem os mesmos dados da última consulta
  # que ainda conta — rodando, ou encerrada com entrega há pouco —, então nenhuma execução é aberta:
  # o modelo recebe o estado dela e responde ao cliente sobre o andamento. Registrado como recusa
  # (entrega 6), com o motivo próprio. NENHUMA linha aqui lê a frase do cliente: quem distingue
  # "e aí?" de "quero mudar a franquia" é o modelo; o código compara dados, e dado diferente abre.
  def recusar_pela_repeticao(run, delivery)
    ::Autonomia::Agents::Tools::Recusa.registrar(
      ::Autonomia::Agents::Tools::PedidoRepetido::MOTIVO, slug: slug, agente: @agent, onde: 'aceite',
                                                          conversa: ::Autonomia::Agents::Tools::Recusa.conversa_de(delivery)
    )
    ::Autonomia::Agents::Tools::PedidoRepetido.new(run).to_s
  end

  # A conferência da própria ferramenta, ainda no turno, na instância já montada — e o invariante
  # que `bound_async_spec` guarda continua valendo onde ele importa: o que não pode segurar o turno é
  # o TRABALHO (`start`, com o teto de 60 s do conector), não uma conferência que não toca no portal
  # e tem teto de 10 s. Falha aqui é nil: aceita e segue.
  def precheck_native(ferramenta)
    ferramenta.precheck.presence
  rescue StandardError => e
    Rails.logger.warn("[autonomia][tool] precheck falhou slug=#{slug} #{e.class}")
    nil
  end

  # A identidade do pedido, da mesma instância (a conferência é uma só). Falha aqui é nil: sem
  # identidade não se barra — o custo é a duplicata que já existia, nunca uma cotação a menos.
  def pedido_native(ferramenta)
    ferramenta.pedido.presence
  rescue StandardError => e
    Rails.logger.warn("[autonomia][tool] pedido falhou slug=#{slug} #{e.class}")
    nil
  end

  # Por que a ferramenta assíncrona NÃO pode ser aceita agora, ou nil. Códigos curtos: o modelo lê,
  # entende que não vai acontecer e explica ao cliente com as próprias palavras.
  def async_refusal(delivery)
    return 'async_indisponivel_nesta_superficie' if delivery&.conversation.blank?
    return 'async_desligado' unless AsyncConfig.enabled?(@agent)
    return 'execucao_ja_aberta_neste_turno' if turn_already_opened?(delivery)

    nil
  end

  # Retry do turno (o settle do ReplyJob reexecutou e o modelo pediu a mesma ferramenta de novo):
  # não abre outra. Uma mensagem NOVA do cliente tem outro `origin_message_id` e passa — e aí o
  # supersede do `open!` é o comportamento certo, porque o pedido mudou.
  def turn_already_opened?(delivery)
    ::Autonomia::Agents::ToolRun.opened_for_turn?(delivery.conversation.id, slug,
                                                  delivery.origin_message_id)
  end

  def run_http(args, delivery)
    Autonomia::Agents::Tools::HttpExecutor.new(tool: @record, params: args).call
  rescue Autonomia::Agents::Tools::HttpExecutor::Error => e
    categoria, status = http_error_code(e.message)
    recusar(categoria, delivery, detalhe: status)
  end

  # Defesa na FRONTEIRA com o modelo. Hoje a mensagem do executor é segura ("tool_http_error:
  # 404 Not Found" — só status e frase padrão do HTTP), mas repassá-la inteira é uma porta aberta:
  # basta alguém, um dia, incluir corpo de resposta ou URL na exceção para vazar sem ninguém notar.
  # Aqui só passa o que é útil ao modelo e comprovadamente inócuo: a CATEGORIA do erro e o status
  # numérico. Texto livre é descartado. -> [categoria, status ou nil].
  def http_error_code(message)
    text = message.to_s
    kind = text.split(':').first.to_s.strip.presence || 'tool_http_error'
    kind = 'tool_http_error' unless kind.match?(/\A[a-z_]+\z/)
    [kind, text[/\b([1-5]\d{2})\b/, 1]]
  end

  # A nativa carrega credencial e assinatura; a mensagem da exceção pode conter requisição assinada.
  # Por isso o rescue é largo e a saída é um código, nunca `e.message`.
  def run_native(args, delivery)
    @native.new(agent: @agent, params: args, delivery: delivery).call
  rescue StandardError => e
    Rails.logger.warn("[autonomia][tool] native failed slug=#{slug} #{e.class}")
    recusar('tool_execution_error', delivery)
  end
end
