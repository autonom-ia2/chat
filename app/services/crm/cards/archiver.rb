# Arquivar um card, o mesmo caminho para a pessoa (Api::V1::Accounts::Crm::CardsController#destroy), o lote
# (Crm::Cards::BulkAction) e a IA (Crm::Ai::NaoENegocio e o aceite do "era teste", Crm::Ai::FecharCard::Aceite).
#
# Arquivado, o card não tem mais o que fazer: as sugestões de etapa da IA pendentes expiram; os lembretes, tarefas e
# follow-ups ainda por vencer são cancelados (motivo `card_archived`, o mesmo que o DueProcessor usa); e o lembrete que
# repete deixa de repetir. O card ganho ou perdido continua nos Números (Crm::Card::DESFECHO_ARQUIVADO).
#
# A reunião marcada com o cliente NÃO é cancelada: cancelar avisa o cliente (convite do calendário ou WhatsApp), e isso
# é decisão de quem atende, pela tela da reunião. Ela fica, com o lembrete dela, e a atividade do arquivamento registra
# quais ficaram (`reunioes_mantidas`).
class Crm::Cards::Archiver
  MOTIVO = 'card_archived'.freeze

  def initialize(card:, actor:, payload: {})
    @card = card
    @actor = actor
    @payload = payload.to_h
    @now = Time.current
  end

  # true quando arquivou; false quando o card já estava arquivado (nada muda, nada é registrado).
  def perform
    return false if @card.archived?

    ActiveRecord::Base.transaction do
      @card.update!(status: :archived, last_activity_at: @now)
      expirar_sugestoes!
      cancelados = cancelar_lembretes!
      encerrar_series!
      Crm::FollowUps::CardNextDueUpdater.update(@card)
      Crm::ActivityLogger.new(card: @card, actor: @actor, event_type: 'archive', payload: registro(cancelados)).perform
    end
    true
  end

  private

  def expirar_sugestoes!
    @card.account.crm_ai_stage_suggestions.where(card: @card, status: :pending).find_each { |sugestao| sugestao.update!(status: :expired) }
  end

  def cancelar_lembretes!
    lembretes = @card.follow_ups.active.where.not(id: reunioes_mantidas.filter_map(&:reminder_id))
    lembretes.find_each.count do |lembrete|
      lembrete.update!(status: :canceled, canceled_at: @now, metadata: lembrete.metadata.to_h.merge('canceled_reason' => MOTIVO))
    end
  end

  def encerrar_series!
    Crm::FollowUpSeries.where(account_id: @card.account_id, card_id: @card.id, status: %i[active paused])
                       .find_each { |serie| serie.update!(status: :ended, ended_at: @now) }
  end

  def reunioes_mantidas
    @reunioes_mantidas ||= Crm::Meeting.where(account_id: @card.account_id, card_id: @card.id).upcoming.to_a
  end

  def registro(cancelados)
    extra = {}
    extra[:lembretes_cancelados] = cancelados if cancelados.positive?
    extra[:reunioes_mantidas] = reunioes_mantidas.map(&:id) if reunioes_mantidas.any?
    @payload.merge(extra)
  end
end
