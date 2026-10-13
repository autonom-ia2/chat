# A fila de quem espera uma pessoa (a cada 2 minutos, config/schedule.yml).
#
# 1. Conversas que o motor de entrega segura (Crm::Entrega::Marca, #1454): tenta de novo, com a mesma regra, e entrega
#    para quem tiver ficado online. Vale com ou sem CRM e sem a IA do CRM ligada: é o "segura e entrega quando alguém
#    entrar" da caixa sem regra também. O convite que venceu (TTL da etapa) só perde a marca, e a conversa volta a poder
#    ser pega pelo rodízio nativo.
# 2. Cards com a espera gravada no card, de antes do #1454 (só com a IA do CRM ligada), pelo HandoffExecutor.
class Crm::Ai::HandoffDrainJob < ApplicationJob
  queue_as :scheduled_jobs

  # Conversas que o motor segura, por rodada. A consulta entra pelo índice parcial
  # index_conversations_on_crm_entrega_pendente, que só tem as marcadas. Com mais que isso na fila, a rodada seguinte
  # continua de onde esta parou (cursor no Redis) e, no fim, volta ao começo: nenhuma conversa fica sempre de fora.
  CONVERSAS_POR_RODADA = 500
  CURSOR_KEY = 'crm:entrega:fila:cursor'.freeze

  def perform
    drain_held_conversations
    return unless Crm::Ai::Config.enabled?

    Crm::Pipeline.active.find_each do |pipeline|
      held_cards(pipeline).find_each { |card| drain(card) if drainable?(card) }
    end
  end

  private

  # Abertas (ou pendentes, legado) e sem pessoa: a marca sai sozinha quando alguém é atribuído ou a conversa resolve.
  # Adiada fica de fora de propósito: ninguém atende uma conversa adiada; ela guarda a marca (o rodízio nativo também
  # não a pega) e volta para esta fila quando reabre.
  def held_conversations(after_id)
    Conversation.where(Crm::Entrega::Marca::PRESENTE_SQL)
                .where(status: [Conversation.statuses[:open], Conversation.statuses[:pending]], assignee_id: nil)
                .where('conversations.id > ?', after_id)
                .order(:id).limit(CONVERSAS_POR_RODADA)
  end

  def drain_held_conversations
    ids = held_conversations(read_cursor).pluck(:id)
    Conversation.where(id: ids).order(:id).each do |conversation|
      drain_conversation(conversation)
    rescue StandardError => e
      # Uma conversa com problema não pode travar a fila das outras.
      Rails.logger.error("[crm][entrega] fila conversa=#{conversation.id} erro=#{e.class}")
    end
    write_cursor(ids.size < CONVERSAS_POR_RODADA ? 0 : ids.last)
  end

  # Sem Redis, a rodada começa do início e segue; os cards do CRM (passo 2) também rodam.
  def read_cursor
    Redis::Alfred.get(CURSOR_KEY).to_i
  rescue StandardError => e
    Rails.logger.error("[crm][entrega] fila cursor indisponível erro=#{e.class}")
    0
  end

  def write_cursor(value)
    Redis::Alfred.set(CURSOR_KEY, value)
  rescue StandardError => e
    Rails.logger.error("[crm][entrega] fila cursor não gravado erro=#{e.class}")
  end

  def drain_conversation(conversation)
    if Crm::Entrega::Marca.convite_vencido?(conversation)
      conversation.with_lock do
        Crm::Entrega::Marca.tirar(conversation) if Crm::Entrega::Marca.convite_vencido?(conversation)
        conversation.save! if conversation.changed?
      end
      return
    end

    marca = Crm::Entrega::Marca.dados(conversation)
    return unless marca && marca['modo'] == Crm::Entrega::Marca::SEGURANDO

    Crm::Entrega.new(conversation: conversation, motivo: marca['motivo'], origem: 'fila', pedido: { sugestao: marca['sugestao'] }).call
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
