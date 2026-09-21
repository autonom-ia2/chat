# PR2 — telemetria de tempo-de-pega do convite R3. Quando um humano assume a
# conversa, se havia um convite PENDENTE (invited_at gravado pelo HandoffInviter,
# sem picked_up_at), registra o tempo de pega: relógio de parede e — quando o
# agente tem agenda — segundos ÚTEIS via Sla::BusinessTimeCalculator.
#
# Recebe SNAPSHOT do evento (assignee_id + picked_up_at do momento da atribuição),
# não o estado atual: a fila pode atrasar e a conversa pode ser reatribuída antes
# do job rodar — medir "agora" inflaria o tempo e creditaria o agente errado.
#
# Métrica CRM própria (card.metadata + Crm::Activity 'ai_handoff_pickup'); ZERO
# acoplamento com applied_sla/sla_policy. Idempotente sob concorrência via with_lock.
class Crm::Ai::HandoffPickupRecorder
  def initialize(conversation:, assignee_id:, picked_up_at_iso:)
    @conversation = conversation
    @assignee_id = assignee_id
    @picked_up_at = parse_time(picked_up_at_iso)
  end

  def perform
    return if @assignee_id.blank? || @picked_up_at.blank?

    invited_cards.each { |card| record_pickup(card) }
  end

  private

  # Pré-filtro barato: cards ligados a esta conversa e que tiveram convite R3
  # (invited_at). NÃO exclui os já pegos — o earliest-wins mora no recheck sob lock
  # (senão um snapshot posterior que gravasse primeiro barraria o anterior aqui).
  # r2_direct/atribuição manual normal não gravam invited_at → excluídos.
  def invited_cards
    cards_linked_to_conversation.select do |card|
      card_handoff(card)['invited_at'].present?
    end
  end

  # QUALQUER card ligado a esta conversa, e não só aquele em que ela é a PRIMÁRIA.
  # O card é do contato: a primária fica fixada na primeira conversa dele e toda conversa
  # nova entra como secundária em crm_card_conversations. Desde a #553 o convite vai para a
  # conversa viva, que costuma ser uma secundária — procurando só por `conversation_id` não
  # se achava card nenhum e o ciclo nunca fechava. O corretor sentia isso em três lugares:
  # badge "aguardando pega" preso no kanban, escalada em cima de quem já tinha pegado, e o
  # cooldown de 6h segurando o próximo pedido do cliente (issue #556).
  def cards_linked_to_conversation
    Crm::Card.where(conversation_id: @conversation.id)
             .or(Crm::Card.where(id: linked_card_ids))
  end

  def linked_card_ids
    Crm::CardConversation.where(conversation_id: @conversation.id).select(:card_id)
  end

  def card_handoff(card)
    (card.metadata || {}).dig('ai', 'handoff') || {}
  end

  # with_lock (FOR UPDATE) + recheck sob lock. Mantém a pega MAIS ANTIGA (a real):
  # sob corrida assign A@t1 / reassign B@t2, a ordem de drenagem da fila não decide
  # quem vence — o snapshot posterior é ignorado. Activity é logada só na 1ª
  # gravação (metadata é a fonte de verdade da métrica), evitando duplicidade.
  def record_pickup(card)
    card.with_lock do
      handoff = card_handoff(card)
      invited_at = parse_time(handoff['invited_at'])
      next if invited_at.blank? || closed_cycle?(handoff)

      existing = parse_time(handoff['picked_up_at'])
      next if existing.present? && existing <= @picked_up_at

      wall = (@picked_up_at - invited_at).round
      business = business_seconds(invited_at, @picked_up_at)

      stamp!(card, handoff, wall, business)
      log!(card, wall, business) if existing.blank?
    end
  end

  # Ciclo fechado (escalado, cancelado por novo convite ou expirado por TTL) não
  # recebe pega: atribuição depois do fechamento é ação nova, não pega do convite.
  def closed_cycle?(handoff)
    handoff['escalated_at'].present? ||
      handoff['canceled_at'].present? ||
      handoff['expired_at'].present?
  end

  # Segundos úteis dentro da agenda do AGENTE que pegou (owner=User). Sem agenda
  # usável → nil (fica só o relógio de parede). BusinessTimeCalculator é overlay
  # enterprise, sempre carregado nesta fork; guarda defined? por segurança.
  def business_seconds(from, to)
    schedule = agent_schedule
    return unless schedule&.usable?
    return unless defined?(Sla::BusinessTimeCalculator)

    Sla::BusinessTimeCalculator.new(schedule: schedule).elapsed_seconds(from, to)
  end

  def agent_schedule
    Crm::ServiceSchedule.find_by(
      account_id: @conversation.account_id,
      owner_type: 'User',
      owner_id: @assignee_id
    )
  end

  # Carimba a pega no ciclo correspondente do array (mesmo cycle_id, senão o convite
  # aberto por invited_at) SEM tocar nos ciclos anteriores — preserva o histórico por
  # ciclo (U11). O ponteiro ai['handoff'] segue apontando p/ o ciclo ativo (retrocompat
  # dos leitores do blob único). Cards legados (sem array) só atualizam o ponteiro.
  def stamp!(card, handoff, wall, business)
    metadata = (card.metadata || {}).deep_dup
    fields = pickup_fields(wall, business)
    merged = handoff.merge(fields)
    ai = metadata['ai'] || {}
    ai['handoffs'] = stamp_cycle(ai['handoffs'], merged, fields)
    ai['handoff'] = merged
    metadata['ai'] = ai
    card.update!(metadata: metadata)
  end

  def pickup_fields(wall, business)
    {
      'picked_up_at' => @picked_up_at.iso8601,
      'picked_up_by' => @assignee_id,
      'pickup_seconds' => wall,
      'business_pickup_seconds' => business
    }
  end

  # Atualiza só o ciclo casado (por cycle_id do ponteiro, senão o convite aberto de
  # mesmo invited_at). Não achou/sem array → devolve como está (o ponteiro cobre o
  # legado).
  def stamp_cycle(cycles, merged, fields)
    return cycles unless cycles.is_a?(Array)

    matched = false
    cycles.map do |cycle|
      if !matched && cycle_matches?(cycle, merged)
        matched = true
        cycle.merge(fields)
      else
        cycle
      end
    end
  end

  def cycle_matches?(cycle, merged)
    return cycle['cycle_id'] == merged['cycle_id'] if merged['cycle_id'].present?

    cycle['invited_at'] == merged['invited_at'] && cycle['picked_up_at'].blank?
  end

  def log!(card, wall, business)
    Crm::ActivityLogger.new(
      card: card,
      actor: nil,
      event_type: 'ai_handoff_pickup',
      conversation: @conversation,
      payload: {
        assignee_id: @assignee_id,
        pickup_seconds: wall,
        business_pickup_seconds: business
      }
    ).perform
  end

  def parse_time(value)
    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
