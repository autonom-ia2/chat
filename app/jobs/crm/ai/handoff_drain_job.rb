# A fila de quem espera uma pessoa (a cada 2 minutos, config/schedule.yml).
#
# 1. Conversas que o motor de entrega segura (Crm::Entrega::Marca, #1454): tenta de novo, com a mesma regra, e entrega
#    para quem tiver ficado online. Vale com ou sem CRM e sem a IA do CRM ligada: é o "segura e entrega quando alguém
#    entrar" da caixa sem regra também. O convite que venceu (TTL da etapa) perde a marca, os administradores da
#    caixa são avisados, e a conversa volta a poder ser pega pelo rodízio nativo.
# 2. Cards com a espera gravada no card, de antes do #1454 (só com a IA do CRM ligada), pelo HandoffExecutor.
#
# Uma rodada por vez (trava de sessão do Postgres; quem não pega, sai), 45 s por passo, ordem alternada, e a presença
# de cada conta lida uma vez (Crm::Entrega::Presenca). O teto é checado entre itens: cada item pode somar até ~10 s
# de trava (LOCK_TIMEOUT na linha e no carimbo), então uma rodada fica perto de 90 s, no pior caso ~110 s.
# A presença fica congelada durante a rodada:
# quem entrar no meio dela recebe na rodada seguinte, 2 minutos depois.
class Crm::Ai::HandoffDrainJob < ApplicationJob
  queue_as :scheduled_jobs

  # Conversas por rodada, as que esperam há mais tempo sem nova tentativa primeiro (`tentado_em` da marca, nunca
  # tentadas antes). Sem estado fora do banco: a fila anda mesmo com o Redis fora do ar, e quem ficou de fora de uma
  # rodada é das primeiras na seguinte. A consulta entra pelo índice parcial idx_conversations_crm_entrega_fila.
  CONVERSAS_POR_RODADA = 500
  # Orçamento de tempo de cada passo (o cron roda a cada 2 minutos). Separados, e a ordem dos passos alterna a cada
  # rodada: uma fila cheia de conversas não deixa os cards sem vez, nem o contrário.
  ORCAMENTO_CONVERSAS = 45
  ORCAMENTO_CARDS = 45
  # Espera máxima pela trava de uma linha (conversa ou card) dentro da fila: ocupada, a conversa é pulada nesta rodada.
  LOCK_TIMEOUT = '5s'.freeze
  # Chave da trava de sessão (pg_try_advisory_lock) que impede duas rodadas ao mesmo tempo.
  TRAVA_DA_RODADA = 1_454_000_001
  TENTADO_EM_SQL = "(conversations.additional_attributes -> 'crm_entrega' ->> 'tentado_em')".freeze

  def perform
    return unless pegar_trava

    begin
      Crm::Entrega::Presenca.na_rodada { passos.each { |passo| send(passo) } }
    ensure
      soltar_trava
    end
  end

  private

  def relogio
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  # O cron roda a cada 2 minutos (minuto sempre par): alterna pela rodada (minuto / 2), conversas primeiro numa,
  # cards primeiro na seguinte.
  def passos
    passos = [:drain_held_conversations]
    passos << :drain_held_cards if Crm::Ai::Config.enabled?
    (Time.current.min / 2).even? ? passos : passos.reverse
  end

  def tempo_acabou?
    relogio > @prazo
  end

  def comecar_passo(orcamento)
    @prazo = relogio + orcamento
  end

  # A trava (SET LOCAL) vale só para a transação desta tentativa.
  def com_lock_timeout(&)
    ActiveRecord::Base.transaction(requires_new: true) do
      ActiveRecord::Base.connection.execute("SET LOCAL lock_timeout = '#{LOCK_TIMEOUT}'")
      yield
    end
  end

  def pegar_trava
    ActiveRecord::Base.connection.select_value("SELECT pg_try_advisory_lock(#{TRAVA_DA_RODADA})")
  end

  # Trava que não sai prenderia a fila para sempre (é da sessão): sem confirmação, a conexão cai e a trava vai junto.
  def soltar_trava
    connection = ActiveRecord::Base.connection
    soltou = begin
      connection.select_value("SELECT pg_advisory_unlock(#{TRAVA_DA_RODADA})")
    rescue StandardError => e
      Rails.logger.error("[crm][entrega] fila trava não soltou erro=#{e.class}")
      false
    end
    return if soltou

    Rails.logger.error('[crm][entrega] fila trava não confirmada: derrubando a conexão')
    connection.disconnect!
  end

  # Abertas (ou pendentes, legado) e sem pessoa: a marca sai sozinha quando alguém é atribuído ou a conversa resolve.
  # Adiada fica de fora de propósito: ninguém atende uma conversa adiada; ela guarda a marca (o rodízio nativo também
  # não a pega) e volta para esta fila quando reabre.
  def held_conversations
    Conversation.where(Crm::Entrega::Marca::PRESENTE_SQL)
                .where(status: [Conversation.statuses[:open], Conversation.statuses[:pending]], assignee_id: nil)
                .order(Arel.sql("#{TENTADO_EM_SQL} ASC NULLS FIRST, conversations.id ASC"))
                .limit(CONVERSAS_POR_RODADA)
  end

  def drain_held_conversations
    comecar_passo(ORCAMENTO_CONVERSAS)
    held_conversations.each do |conversation|
      break if tempo_acabou?

      drain_one(conversation)
    end
  end

  def drain_one(conversation)
    inicio = relogio
    com_lock_timeout { drain_conversation(conversation) }
  rescue ActiveRecord::LockWaitTimeout
    Rails.logger.warn("[crm][entrega] fila conversa=#{conversation.id} pulada: trava ocupada")
  rescue StandardError => e
    # Uma conversa com problema não pode travar a fila das outras.
    Rails.logger.error("[crm][entrega] fila conversa=#{conversation.id} erro=#{e.class}")
  ensure
    Rails.logger.info("[crm][entrega] fila conversa=#{conversation.id} ms=#{((relogio - inicio) * 1000).round}")
    marcar_tentativa(conversation)
  end

  # Só o carimbo da tentativa, direto no JSONB e só se a marca continua lá: sem callbacks nem eventos a cada rodada. Com o
  # mesmo lock_timeout: linha presa por outra transação não segura a rodada (nem a trava de sessão).
  def marcar_tentativa(conversation)
    com_lock_timeout { carimbar_tentativa(conversation) }
  rescue StandardError => e
    # Sem o carimbo a conversa só volta mais cedo na fila; a rodada segue.
    Rails.logger.error("[crm][entrega] fila conversa=#{conversation.id} tentativa não carimbada erro=#{e.class}")
  end

  def carimbar_tentativa(conversation)
    # rubocop:disable Rails/SkipsModelValidations
    Conversation.where(id: conversation.id).where(Crm::Entrega::Marca::PRESENTE_SQL).update_all(
      [
        "additional_attributes = jsonb_set(additional_attributes, '{#{Crm::Entrega::Marca::CHAVE},tentado_em}', to_jsonb(?::text))",
        Time.current.utc.iso8601(6)
      ]
    )
    # rubocop:enable Rails/SkipsModelValidations
  end

  def drain_card(card)
    com_lock_timeout { drain(card) }
  rescue ActiveRecord::LockWaitTimeout
    Rails.logger.warn("[crm][entrega] fila card=#{card.id} pulado: trava ocupada")
  rescue StandardError => e
    Rails.logger.error("[crm][entrega] fila card=#{card.id} erro=#{e.class}")
    ChatwootExceptionTracker.new(e, account: card.account).capture_exception
  end

  def drain_held_cards
    comecar_passo(ORCAMENTO_CARDS)
    Crm::Pipeline.active.find_each do |pipeline|
      break if tempo_acabou?

      held_cards(pipeline).find_each do |card|
        break if tempo_acabou?

        drain_card(card) if drainable?(card)
      end
    end
  end

  def drain_conversation(conversation)
    return Crm::Entrega::ConviteVencido.new(conversation).call if Crm::Entrega::Marca.convite_vencido?(conversation)

    marca = Crm::Entrega::Marca.dados(conversation)
    return unless marca && marca['modo'] == Crm::Entrega::Marca::SEGURANDO
    return largar_para_o_agente(conversation) if da_ia_do_crm_com_agente_nosso?(conversation, marca)
    return if Crm::Entrega::ConviteVencido.espacar?(marca)

    card = Crm::Entrega::Marca.card(conversation)
    Crm::Entrega.new(conversation: conversation, motivo: marca['motivo'], origem: 'fila', pedido: { sugestao: marca['sugestao'] },
                     dono: dono_da_marca(conversation, marca), card: card, pelo_card: card.present?, excluir: marca['venceram'])
                .call.tap { |resultado| nota_do_aviso(conversation, marca, resultado) }
  end

  # #2154 (flag `agente_so_informa`): o agente avisou que ia chamar alguém, a IA de Atribuição decidiu passar e ninguém
  # estava online (a espera com o motivo do pedido do robô). Quando a fila entrega agora, sai a nota "Antes de encaminhar"
  # que o agente não postou, com as recusas guardadas desde o aviso (RecusasRecentes.guardar_ate_a_passagem). Sem a
  # flag, a nota já saiu no bot_handoff! do agente, e nada muda.
  def nota_do_aviso(conversation, marca, resultado)
    return unless %i[entregue convidado].include?(resultado&.status)
    return unless marca['motivo'] == Crm::Ai::HandoffExecutor::MOTIVO_DA_PROMESSA
    return unless Autonomia::Agents::AgenteSoInforma.ligada?(conversation.account)

    Autonomia::Agents::NotaDoEncaminhamento.postar(conversation)
  end

  # #1673: a IA do CRM segurou a conversa sem robô e, na espera, um agente nosso passou a atender (claim da resposta).
  # Ela não tira a conversa dele: a marca sai e o pedido de pessoa fica com a instrução do agente. A espera que nasceu
  # de um pedido do próprio agente (bot_handoff!) tem outro motivo e segue para a entrega.
  def da_ia_do_crm_com_agente_nosso?(conversation, marca)
    marca['motivo'] == Crm::Ai::HandoffExecutor::MOTIVO_DA_ENTREGA && Autonomia::Agents::QuemResponde.dono_ativo(conversation).present?
  end

  def largar_para_o_agente(conversation)
    # Reconfere sob a trava: um pedido novo do próprio agente nesse meio tempo regravou a marca e não pode sumir.
    conversation.with_lock do
      marca = Crm::Entrega::Marca.dados(conversation)
      next unless marca && da_ia_do_crm_com_agente_nosso?(conversation, marca)

      Crm::Entrega::Marca.tirar(conversation)
      conversation.save! if conversation.changed?
    end
    Rails.logger.info("[crm][handoff] conversa=#{conversation.id} gatilho=fila desfecho=skipped " \
                      "motivo=#{Crm::Ai::HandoffExecutor::OWNED_BY_OUR_AGENT}")
  end

  # A pessoa por quem a entrega espera (R13 do #1150), só se ainda é da conta da conversa; a Entrega confere se ela
  # continua na fila de quem cuida.
  def dono_da_marca(conversation, marca)
    return if marca['dono_id'].blank?

    conversation.account.users.find_by(id: marca['dono_id'])
  end

  # Pré-filtro barato no JSONB: o volume esperado é baixo, mas isso evita varrer
  # todo card aberto. A elegibilidade real fica no lock, porque humano/self-assign
  # e outro tick do cron podem mudar conversa/status entre a query e a tentativa.
  def held_cards(pipeline)
    pipeline.cards.open
            .includes(:primary_conversation)
            .where("metadata #>> '{ai,handoff_hold,held_at}' IS NOT NULL")
  end

  # Elegibilidade por CARD (não por pipeline): handoff pode estar ligado só numa
  # etapa. Usa a mesma resolução do executor, onde a etapa vence o padrão do funil.
  def drainable?(card)
    settings = Crm::Ai::Config.handoff_settings(card.stage, card.pipeline)
    settings[:enabled] && settings[:handoff_mode] == 'r2_direct'
  end

  # Drena sem IA: trava a CONVERSA primeiro, na mesma ordem do CardSyncer
  # (conversation→card), para não criar deadlock ABBA. O recheck de assignee_id sob lock fecha a brecha de self-assign
  # humano entre a query do cron e a tentativa de atribuição.
  def drain(card)
    # A MESMA CONVERSA QUE O EXECUTOR VAI ATRIBUIR, e não a primária do card (issue #553): a trava só serializa contra
    # o self-assign humano se travar a linha que vai ser escrita, e o recheck de `assignee_id` lido na conversa errada
    # apagava o marcador de espera para sempre.
    conversation = card.conversa_em_atendimento
    return clear_handoff_hold!(card) if conversation.blank?

    conversation.with_lock do
      next clear_handoff_hold!(card) unless card.reload.open?
      next unless held?(card)
      # Humano assumiu por fora do executor (self-assign) → terminal: limpa o
      # marcador para o card não ser requeriado nem travar a conversa a cada tick.
      next clear_handoff_hold!(card) if conversation.assignee_id.present?

      Crm::Ai::HandoffExecutor.new(card: card, handoff: handoff_payload(card), trigger: 'drain').perform
    end
  end

  def held?(card)
    card.metadata.to_h.dig('ai', 'handoff_hold', 'held_at').present?
  end

  def handoff_payload(card)
    card.metadata.to_h.dig('ai', 'handoff_hold', 'handoff') || {}
  end

  # Sob a trava do card, relendo o metadata: não apaga um carimbo gravado por outra conexão.
  def clear_handoff_hold!(card)
    card.with_lock do
      metadata = (card.metadata || {}).deep_dup
      ai = metadata['ai'] || {}
      next unless ai.key?('handoff_hold')

      metadata['ai'] = ai.except('handoff_hold')
      card.update!(metadata: metadata)
    end
  end
end
