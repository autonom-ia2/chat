# A ABERTURA DA CONSULTA HTTP EM SEGUNDO PLANO (#1430), do lado do turno (`ConsultaNoTurno`): qual execução serve a
# este pedido (a mesma chave, ou o mesmo pedido numa mensagem nova), e a abertura de uma nova com o job enfileirado.
# Separada da espera e da entrega pelo tamanho da classe; usa o estado dela (`@turno`, `@tool`, `@chave`, `@params`,
# `@ocorrencia`, `@agente`).
module Autonomia::Agents::Tools::ConsultaNoTurno::Abertura
  ToolRun = ::Autonomia::Agents::ToolRun
  Chave = ::Autonomia::Agents::Tools::ChaveDeIdempotencia

  private

  # A execução com esta chave que ainda serve: a que roda, a concluída com 2xx (o turno refeito não chama de novo) ou a
  # incerta (a chamada saiu e a resposta se perdeu: chamar de novo poderia registrar o pedido duas vezes lá). A que
  # falhou com certeza não serve: chamar de novo, com a mesma chave, é o que o síncrono faz.
  def reaproveitada
    da_chave = ToolRun.for_conversation(@turno.conversation.id).where(autonomia_agent_tool_id: @tool.id)
                      .where('handle ->> ? = ?', ToolRun::CHAVE_DA_CONSULTA, @chave)
    servem = da_chave.where("status = 'running' OR (status = 'done' AND handle @> ?)", { ToolRun::RESULTADO_OK => true }.to_json)
    servem.order(id: :desc).first || incerta_recente(da_chave)
  end

  # Sob a trava da faixa, para duas passadas do mesmo pedido não abrirem duas. O job sai DEPOIS do commit.
  def abrir
    nova = false
    run = ToolRun.transaction do
      ToolRun.travar!(@turno.conversation.id, @tool.slug, faixa)
      existente = reaproveitada || pendurada
      next existente if existente

      nova = true
      aberta
    end
    enfileirar(run) if nova
    run
  end

  # O MESMO PEDIDO NUMA MENSAGEM NOVA: a execução viva da faixa que já chamou o sistema de fora é a deste turno também
  # (chamar de novo, com outra chave, gravaria o pedido duas vezes lá). A que ainda não chamou é trocada pela nova. A
  # incerta da faixa também segura o pedido: o turno lê a incerteza, sem chamar o sistema de fora.
  def pendurada
    da_faixa = ToolRun.for_conversation(@turno.conversation.id).where(slug: @tool.slug, faixa: faixa)
    incerta = incerta_recente(da_faixa)
    return incerta if incerta

    viva = da_faixa.find_by(status: 'running')
    return entregue_a_turno_que_nao_falou(da_faixa) if viva.nil?
    return nil if viva.superar_sem_chamada!

    viva.reload.running? ? viva : nil
  end

  # A INCERTA SEGURA O PEDIDO SÓ ENQUANTO É RECENTE: o tempo da ferramenta mais a carência do varredor
  # (`ReapStaleRunsJob::GRACE`), contados do fechamento — a mesma janela em que a chamada original ainda podia estar em
  # voo. Depois disso (a incerta de segunda, a mesma pergunta na sexta), é pedido novo, e chama de novo. Sem fechamento
  # (a linha viva que o job deixou para o turno), segura.
  def incerta_recente(escopo)
    limite = recente_desde
    escopo.where('handle @> ?', { ToolRun::CODIGO_DA_CONSULTA => ToolRun::INCERTA }.to_json)
          .where('(handle->>?) IS NULL OR (handle->>?)::timestamptz >= ?', ToolRun::ENCERRADA_EM, ToolRun::ENCERRADA_EM, limite)
          .order(id: :desc).first
  end

  def recente_desde
    @tool.timeout_seconds.to_i.seconds.ago - ::Autonomia::Agents::Tools::ReapStaleRunsJob::GRACE
  end

  # O TURNO QUE ENTREGOU, FECHOU A LINHA E FOI SUPERADO SEM POSTAR: o resultado é deste turno (`entrega_deste_turno?`
  # toma a marca por compare-and-set), sem chamar o sistema de fora de novo. Só a recente e só se nenhuma fala do robô
  # saiu depois do fechamento: com a fala, o resultado foi dito, e o pedido igual é outro pedido.
  def entregue_a_turno_que_nao_falou(da_faixa)
    run = da_faixa.where(status: 'done').where('handle @> ?', { ToolRun::ENTREGA => ToolRun::ENTREGUE_NO_TURNO }.to_json)
                  .order(id: :desc).first
    return nil if run.nil? || run.entregue_por == @turno.turno || !turno_superado?(run.entregue_por)

    encerrada_em = Time.zone.parse(run.handle.to_h[ToolRun::ENCERRADA_EM].to_s)
    return nil if encerrada_em.nil? || encerrada_em < recente_desde

    falou = @turno.conversation.messages.outgoing.where(sender_type: 'AgentBot').exists?(['created_at > ?', encerrada_em])
    falou ? nil : run
  end

  def aberta
    run = ToolRun.open!(agent: @agente, slug: @tool.slug, arguments: @params, marcas: marcas, scope: escopo)
    raise ActiveRecord::RecordNotUnique, "consulta #{@tool.slug} não abriu" if run.nil?

    run.promote!(expected_chunks: 0, notify_customer: false,
                 expires_at: ::Autonomia::Agents::Tools::HttpAssincronaJob.vence_em(@tool.timeout_seconds))
    run
  end

  # Sem o job, a linha não pode ficar viva esperando quem nunca vem: fecha sem evento (o turno ainda não desistiu) e
  # sobe, para o turno recusar.
  def enfileirar(run)
    ::Autonomia::Agents::Tools::HttpAssincronaJob.perform_later(run.id)
  rescue StandardError
    run.finish!('failed', failure_code: 'consulta_nao_disparou')
    raise
  end

  def marcas
    { ToolRun::CHAVE_DA_CONSULTA => @chave, ToolRun::TEMPO_DA_CONSULTA => @tool.timeout_seconds,
      ToolRun::ABERTA_EM => Time.current.iso8601(3) }
  end

  def escopo
    { conversation_id: @turno.conversation.id, agent_inbox_id: @turno.agent_inbox&.id, faixa: faixa,
      origin_message_id: @turno.origin_message_id, autonomia_agent_tool_id: @tool.id }
  end

  # A faixa é o pedido (a ferramenta, os argumentos tipados e a ocorrência, sem o turno): outro pedido corre junto, e
  # duas chamadas idênticas da mesma rodada também; o mesmo, numa mensagem nova, cai na mesma faixa (`pendurada`).
  def faixa
    @faixa ||= "#{ToolRun::FAIXA_DA_CONSULTA}#{::Autonomia::Insurance::Faixa::SEPARADOR}" \
               "#{Chave.resumo([@tool.id, Chave.em_ordem(@params), @ocorrencia.to_i])[0, 16]}"
  end
end
