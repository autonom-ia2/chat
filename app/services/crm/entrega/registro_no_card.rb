# O que a entrega grava no card quando segue a regra da Atribuição do funil (#1454): o carimbo da última passagem
# (intervalo anti-repetição e "Devolver para a IA"), o ciclo do convite (métrica de tempo de pega, escalada e
# expiração) e a atividade na linha do tempo. Extraído do Crm::Ai::HandoffExecutor sem mudar o formato do JSONB:
# PickupRecorder, EscalationJob, ExpiryJob e o Kanban continuam lendo os mesmos campos.
class Crm::Entrega::RegistroNoCard
  # Limita o histórico de convites por card para o JSONB não crescer sem fim.
  HANDOFF_CYCLES_CAP = 20
  # Um ciclo com qualquer um destes carimbos já terminou.
  FECHAMENTOS = %w[picked_up_at canceled_at expired_at escalated_at].freeze

  def initialize(card:, conversation:, settings:)
    @card = card
    @conversation = conversation
    @settings = settings
  end

  def entregue!(pessoa, razao: nil)
    carimbar!
    atividade!(pessoa, 'ai_handoff', razao)
  end

  def convidado!(pessoa, razao: nil)
    carimbar!(convidado: pessoa)
    atividade!(pessoa, 'ai_handoff_invite', razao)
  end

  # Passagem recente demais para repetir (anti-spam de convite e de repasse). Um ciclo resolvido (alguém pegou e
  # devolveu) libera na hora.
  def intervalo_ativo?
    last = ai_meta['last_handoff_at']
    return false if last.blank?
    return false if ciclo_resolvido?

    Time.zone.parse(last.to_s) > Crm::Ai::Config::HANDOFF_COOLDOWN_SECONDS.seconds.ago
  rescue ArgumentError, TypeError
    false
  end

  private

  def ai_meta
    (@card.metadata || {}).fetch('ai', {}).to_h
  end

  def convite?
    @settings[:handoff_mode] == 'r3_invite'
  end

  # Ciclo pego e depois liberado = passagem RESOLVIDA: uma pessoa assumiu (picked_up_at) e a conversa voltou a ficar
  # sem ninguém. Ciclos abertos, cancelados, expirados ou escalados mantêm o intervalo.
  def ciclo_resolvido?
    pointer = ai_meta['handoff']
    return true if pointer.is_a?(Hash) && pointer['picked_up_at'].present?
    return false if convite?

    devolvida_depois_da_entrega_direta?
  end

  # A entrega direta não grava ciclo: uma passagem anterior somada à conversa AGORA sem ninguém é a assinatura de
  # "pessoa assumiu e devolveu". Carimbo de convite nunca libera por aqui (convite pendente com a etapa trocada).
  def devolvida_depois_da_entrega_direta?
    return false if ai_meta['last_handoff_at'].blank?
    return false if ai_meta['last_handoff_mode'] == 'invite'

    @conversation&.assignee_id.blank?
  end

  def carimbar!(convidado: nil)
    metadata = (@card.metadata || {}).deep_dup
    now = Time.current.iso8601
    ai = (metadata['ai'] || {}).merge('last_handoff_at' => now, 'last_handoff_mode' => convidado ? 'invite' : 'direct')
    ai.delete('handoff_hold')
    ai = acrescentar_ciclo(ai, now, convidado) if convidado
    metadata['ai'] = ai
    @card.update!(metadata: metadata)
  end

  # Cada convite é um CICLO em ai['handoffs'], com o ponteiro ai['handoff'] no ciclo ativo. Um ciclo novo encerra o
  # anterior ainda aberto (canceled_at) sem pisar na métrica dele.
  def acrescentar_ciclo(ai_meta, now, pessoa)
    ciclos = encerrar_abertos(ciclos_normalizados(ai_meta), now)
    ciclo = {
      'cycle_id' => (ciclos.map { |item| item['cycle_id'].to_i }.max || 0) + 1,
      'invited_at' => now,
      'invited_agent_id' => pessoa.id,
      'pickup_due_at' => (Time.current + @settings[:pickup_threshold_seconds].to_i.seconds).iso8601
    }
    ai_meta.merge('handoffs' => (ciclos + [ciclo]).last(HANDOFF_CYCLES_CAP), 'handoff' => ciclo)
  end

  # Convite gravado antes da lista existir vira o ciclo 1, para não perder um convite em voo.
  def ciclos_normalizados(ai_meta)
    ciclos = ai_meta['handoffs']
    return ciclos if ciclos.is_a?(Array) && ciclos.present?

    legado = ai_meta['handoff']
    return [] if legado.blank? || legado['invited_at'].blank?

    [legado.merge('cycle_id' => 1)]
  end

  def encerrar_abertos(ciclos, now)
    ciclos.map do |ciclo|
      aberto = FECHAMENTOS.all? { |campo| ciclo[campo].blank? }
      aberto ? ciclo.merge('canceled_at' => now) : ciclo
    end
  end

  def atividade!(pessoa, event_type, razao)
    Crm::ActivityLogger.new(
      card: @card, actor: nil, event_type: event_type, conversation: @conversation,
      payload: { assignee_id: pessoa.id, reason: razao.to_s[0, 300], mode: @settings[:mode] }
    ).perform
  end
end
