# Roda UM turno do especialista (#311) e devolve TEXTO para o agente principal.
#
# O principal chama `consultar_<slug>` com um pedido em português. Aqui o especialista roda seu
# próprio ciclo — instrução própria, ferramentas próprias — e responde em prosa. O principal
# parafraseia; nunca vê estrutura, nunca vê as ferramentas do especialista.
#
# NUNCA LEVANTA. Qualquer falha vira uma frase curta que volta ao principal como saída da
# função, do mesmo jeito que `Autonomia::Agents::Tools::HttpExecutor` faz: o turno segue e o cliente recebe
# resposta, em vez de silêncio. A mensagem nunca carrega o prompt nem detalhe de credencial.
class Autonomia::Agents::Specialists::Runner
  # O especialista responde em prosa, mas com formato garantido — assim ele não devolve JSON
  # cru para o principal parafrasear nem inventa um formato diferente a cada turno.
  RESULT_SCHEMA = {
    name: 'autonomia_specialist_result',
    schema: {
      type: 'object',
      properties: {
        # O que o principal vai parafrasear. Texto corrido, em português.
        resposta: { type: 'string' },
        # O que ainda falta para concluir. O principal usa isto para saber o que perguntar ao
        # cliente — sem ter que conhecer os campos do ramo.
        dados_faltando: { type: 'array', items: { type: 'string' } }
      },
      required: %w[resposta dados_faltando],
      additionalProperties: false
    }
  }.freeze

  MAX_REQUEST_CHARS = 6_000
  MAX_OUTPUT_CHARS = 6_000
  MAX_TOOL_OUTPUT_CHARS = 8_000
  # RODADAS DE FERRAMENTA POR TURNO (#585). Com uma só — o padrão do cliente —, a recusa da conferência
  # chegava na ida de FECHAMENTO, já sem ferramenta: o especialista sabia a troca e não podia chamar de
  # novo, e em 21/09/2026 isso virou "vou seguir" sem cotação. Seis, por decisão do Rodrigo no mesmo dia,
  # e SEM o relógio cortar nenhuma: o orçamento cobre cada rodada no teto de uma chamada. O que limita é a
  # rodada; a guarda de uma execução por turno continua impedindo duas cotações. Roda no ReplyJob, fora
  # de requisição web.
  RODADAS_DE_FERRAMENTA = 6
  SEGUNDOS_POR_CHAMADA = 120
  SEGUNDOS_DE_FERRAMENTA = RODADAS_DE_FERRAMENTA * SEGUNDOS_POR_CHAMADA
  FEATURE = 'agente_especialista'.freeze
  INDISPONIVEL = 'Especialista indisponível no momento.'.freeze

  # A SITUAÇÃO DA COTAÇÃO, DITA PELO SISTEMA (#585). O principal só conhece a prosa do especialista, e
  # em 21/09/2026 (conversa display 73) a conferência recusou a cotação e a Lia disse ao cliente "Vou
  # seguir com assistência completa…" sem nada aberto. Se a cotação abriu quem sabe é o `Delivery`,
  # não o modelo: quando o especialista tentou uma ferramenta assíncrona, o resultado sai com uma destas
  # frases no fim. É para o principal, não para o cliente — ele continua escrevendo com as palavras dele.
  COTACAO_ABERTA = 'SITUAÇÃO DA COTAÇÃO, dita pelo sistema: a cotação foi aberta nesta consulta.'.freeze
  COTACAO_NAO_ABERTA = 'SITUAÇÃO DA COTAÇÃO, dita pelo sistema: nenhuma cotação foi aberta nesta consulta. ' \
                       'Não diga ao cliente que vai cotar, que está cuidando da cotação nem que vai seguir com ela. ' \
                       'Diga o que falta, faça a pergunta, ou conte que ainda não foi possível cotar.'.freeze
  COTACAO_EXISTENTE = 'SITUAÇÃO DA COTAÇÃO, dita pelo sistema: nenhuma cotação nova foi aberta nesta consulta porque ' \
                      'esta conversa já tem uma, em andamento ou concluída. Fale dela; não diga que abriu outra.'.freeze

  # `history` e `documents` são o que o PRINCIPAL recebeu neste turno (entrega 1): a conversa
  # pública e os PDFs anexados agora. O especialista os lê ANTES do bilhete — é o que faz o CPF que
  # o cliente escreveu chegar ao formulário mesmo quando o principal não o repetiu no pedido, e a
  # apólice em PDF alimentar a renovação sem ninguém digitar.
  def initialize(specialist:, request:, delivery: nil, history: [], documents: [])
    @specialist = specialist
    @request = request.to_s.strip
    # CONTEXTO DE ENTREGA (#313), repassado do principal. É por aqui que a ferramenta ASSÍNCRONA
    # funciona no caminho que importa: o `Answerer` REMOVE do principal todo slug reservado por um
    # especialista habilitado, então a cotação só é alcançável a partir daqui.
    @delivery = delivery
    @history = history
    @documents = documents
  end

  # -> String (sempre). Nunca nil, nunca exceção.
  #
  # CADA SAÍDA EM QUE O ESPECIALISTA NÃO TRABALHA É REGISTRADA (entrega 6). A cotação só é
  # alcançável por aqui; quando o especialista não roda, o pedido de cotar morreu antes da
  # ferramenta — e até 10/09/2026 uma credencial em branco deixava ZERO rastro.
  def call
    return recusar('especialista_sem_pedido', 'O especialista não recebeu um pedido.') if @request.blank?

    credential = Crm::Ai::CredentialResolver.new(account: @specialist.account).resolve
    return recusar('especialista_sem_credencial', INDISPONIVEL) if credential.blank?

    parsed = generate(credential)
    com_situacao(parsed.nil? ? recusar('especialista_sem_resposta', INDISPONIVEL) : format_result(parsed))
  rescue StandardError => e
    # NUNCA ecoar e.message: pode conter o prompt ou a requisição assinada.
    Rails.logger.warn("[autonomia][specialist] failed specialist=#{@specialist.id} #{e.class}")
    com_situacao(recusar('especialista_falhou', INDISPONIVEL))
  end

  private

  def generate(credential)
    @abertas_antes = @delivery&.runs&.size.to_i
    raw = Crm::Ai::ResponsesClient.new(
      credential: credential, feature: FEATURE, account: @specialist.account
    ).create_with_tool_executor(
      model: Autonomia::Agents::Config::ANSWERER_MODEL,
      instructions: @specialist.effective_instruction,
      input: entrada,
      schema: RESULT_SCHEMA,
      reasoning_effort: Autonomia::Agents::Config::ANSWERER_REASONING_EFFORT,
      tools: tool_schemas,
      timeout: SEGUNDOS_POR_CHAMADA,
      max_rodadas: RODADAS_DE_FERRAMENTA,
      max_segundos: SEGUNDOS_DE_FERRAMENTA
    ) { |calls| execute_tool_calls(calls) }
    parsed = JSON.parse(raw[:text])
    parsed.is_a?(Hash) ? parsed : nil
  rescue Crm::Ai::ResponsesClient::Error, JSON::ParserError
    nil
  end

  # A conversa e os documentos primeiro, o bilhete por último. É a POSIÇÃO no prompt, não uma
  # autorização: o que o especialista pode fazer é o catálogo dele que decide (`specialist_tools`),
  # e o modelo é quem decide se faz — a conversa e os anexos entram como dado, cercados.
  def entrada
    materia = Autonomia::Agents::Specialists::Materia.new(delivery: @delivery, history: @history,
                                                          documents: @documents, agent: @specialist.agent)
    pedido = "PEDIDO DO ATENDENTE:\n#{Autonomia::Agents::Config.truncate_text(@request, MAX_REQUEST_CHARS)}"
    materia.mensagens + [Autonomia::Agents::PromptParts::Mensagem.montar('user', pedido)]
  end

  def tool_schemas
    specialist_tools.map(&:openai_schema).presence
  end

  def specialist_tools
    @specialist_tools ||= @specialist.tools
  end

  # Mesmo contrato do Answerer: cada chamada vira um `function_call_output`. Ferramenta
  # desconhecida não derruba o turno — devolve erro nomeado e o modelo decide o que fazer.
  def execute_tool_calls(calls)
    by_slug = specialist_tools.index_by(&:slug)
    Array(calls).map do |call|
      tool = by_slug[call['name'].to_s]
      @tentou_cotar = true if tool&.async?
      output = tool.present? ? tool.execute(call, delivery: @delivery) : sem_ferramenta(call)
      { type: 'function_call_output', call_id: call['call_id'],
        output: output.to_s.truncate(MAX_TOOL_OUTPUT_CHARS) }
    end
  end

  # Ferramenta que o especialista não tem: recusa nomeada E REGISTRADA (entrega 6). Foi exatamente
  # assim que a Lia ficou muda em 08/09/2026 — especialista nascido sem `cotar_seguro` —, e nada
  # dizia isso em lugar nenhum.
  # Chamada pela constante, sem apelido local: a varredura reconhece a saída pelo receptor `Recusa`.
  def sem_ferramenta(call)
    Autonomia::Agents::Tools::Recusa.para_modelo(
      'tool_not_available', slug: Autonomia::Agents::Tools::Recusa.slug_conhecido(call['name'], @specialist.agent),
                            delivery: @delivery, agente: @specialist.agent
    )
  end

  # Recusa em PROSA ao principal, registrada com a conversa (o `delivery` desce do principal) e o
  # agente dono do especialista. O texto que o principal lê não muda.
  def recusar(codigo, texto)
    Autonomia::Agents::Tools::Recusa.registrar(codigo, slug: @specialist.function_name, agente: @specialist.agent,
                                                       conversa: Autonomia::Agents::Tools::Recusa.conversa_de(@delivery))
    texto
  end

  # O texto que vai ao principal, com a situação da cotação no fim quando o especialista tentou uma
  # ferramenta assíncrona. Sem tentativa (uma dúvida respondida), nada é acrescentado.
  def com_situacao(texto)
    return texto unless @tentou_cotar

    [texto, situacao].join(' ')
  end

  def situacao
    return COTACAO_ABERTA if @delivery&.runs&.size.to_i > @abertas_antes.to_i
    return COTACAO_EXISTENTE if @delivery.try(:cotacao_existente?)

    COTACAO_NAO_ABERTA
  end

  # Junta resposta e pendências numa string só — o principal recebe texto, não estrutura.
  def format_result(parsed)
    resposta = parsed['resposta'].to_s.strip
    faltando = Array(parsed['dados_faltando']).map { |item| item.to_s.strip }.reject(&:blank?)
    return recusar('especialista_nao_concluiu', 'O especialista não conseguiu concluir.') if resposta.blank? && faltando.empty?

    parts = [resposta.presence]
    parts << "Ainda falta: #{faltando.join(', ')}." if faltando.any?
    Autonomia::Agents::Config.truncate_text(parts.compact.join(' '), MAX_OUTPUT_CHARS)
  end
end
